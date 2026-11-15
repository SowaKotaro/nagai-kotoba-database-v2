# -*- coding: utf-8 -*-
"""本番の代表的なページを Lighthouse（Google 公式の診断）で測る道具。月次の点検とは別に、UI を大きく変えたあとなどに随時回す。

`script/seo_site_check.py` が見るのは検索エンジンから見える規則（noindex・canonical・301）で、これが見るのはブラウザで開いたときの
性能・アクセシビリティ・SEO の基礎。手順の正は docs/seo-operations.md §10。
Lighthouse は npx で都度取り寄せる（プロジェクトの依存には足さない）。Node と Chrome が要る。本番へは、ページを 1 枚ずつ開く
ぶんの読み込みを送る（1 枚につきブラウザ 1 回の表示と同じ）。

    python3 script/seo_lighthouse.py 2026-11            # 既定のページ
    python3 script/seo_lighthouse.py 2026-11 /rankings  # ページを指定

Chrome は環境変数 CHROME_PATH、無ければ Selenium Manager が入れた最新のもの（~/.cache/selenium/chrome）を使う。

出力（gitignore 済み）:
  research/outputs/seo/<月>/lighthouse.md          点数と、満点でない項目の表
  research/outputs/seo/<月>/lighthouse/<名前>.html  Lighthouse の報告書（ブラウザで開く）
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_ROOT = os.path.join(ROOT, "research", "outputs", "seo")
JP_HOST = "nagai-kotoba-database.jp"
USER_AGENT = "seo-lighthouse"
# 既定で測るページ（型ごとに 1 枚）。単語詳細は一覧の先頭の語を足す。
PAGES = ["/", "/words", "/stats"]
INTERVAL = 3.0   # ページとページのあいだに空ける間隔（秒）。Puma は 1 プロセスなので詰めない
TIMEOUT = 180    # 1 枚の計測の上限（秒）
CATEGORIES = ["performance", "accessibility", "best-practices", "seo"]
# sudo の無い WSL で Chrome の依存ライブラリを展開してある場所（あれば使う）。
CHROME_DEPS = os.path.expanduser("~/.local/chrome-deps/usr/lib/x86_64-linux-gnu")


def version_key(path):
    return [int(part) for part in re.findall(r"\d+", path.split("linux64/")[-1])]


def chrome_path():
    if os.environ.get("CHROME_PATH"):
        return os.environ["CHROME_PATH"]
    found = glob.glob(os.path.expanduser("~/.cache/selenium/chrome/linux64/*/chrome"))
    return max(found, key=version_key) if found else None


def first_word_path():
    """一覧の先頭にある単語詳細のパス。取れなければ None（単語詳細を測らずに進む）。"""
    request = urllib.request.Request(f"https://{JP_HOST}/words", headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode("utf-8", "replace")
    except OSError:
        return None
    match = re.search(r'href="(/words/\d+)"', body)
    return match.group(1) if match else None


def slug(path):
    return re.sub(r"[^a-z0-9]+", "-", path.lower()).strip("-") or "home"


def measure(path, chrome, report_dir):
    """1 枚測って Lighthouse の結果（dict）を返す。測れなければ None。"""
    env = dict(os.environ)
    if chrome:
        env["CHROME_PATH"] = chrome
    if os.path.isdir(CHROME_DEPS):
        env["LD_LIBRARY_PATH"] = CHROME_DEPS + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    # 作業用のディレクトリで動かす（WSL では Chrome のプロファイルがカレントに作られるので、測り終えたら丸ごと消す）。
    work = tempfile.mkdtemp(prefix="seo-lighthouse-")
    command = [
        "npx", "--yes", "lighthouse@latest", f"https://{JP_HOST}{path}", "--quiet",
        "--chrome-flags=--headless=new --no-sandbox",
        "--only-categories=" + ",".join(CATEGORIES),
        "--output=json", "--output=html", "--output-path=" + os.path.join(work, "page"),
    ]
    try:
        subprocess.run(command, cwd=work, env=env, timeout=TIMEOUT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        with open(os.path.join(work, "page.report.json"), encoding="utf-8") as file:
            result = json.load(file)
        shutil.copy(os.path.join(work, "page.report.html"), os.path.join(report_dir, slug(path) + ".html"))
        return result
    except subprocess.CalledProcessError as error:
        print(f"  測れなかった: {error.stderr.decode('utf-8', 'replace').strip()[-300:]}", file=sys.stderr)
    except (OSError, subprocess.TimeoutExpired, ValueError) as error:
        print(f"  測れなかった: {error}", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return None


def findings(result):
    """満点でない項目を (カテゴリ, 題, 表示値) で返す（点数に効く項目だけ）。"""
    rows = []
    for key in CATEGORIES:
        for ref in result["categories"][key]["auditRefs"]:
            audit = result["audits"][ref["id"]]
            if ref.get("weight", 0) > 0 and audit.get("score") is not None and audit["score"] < 1:
                rows.append((key, audit["title"], audit.get("displayValue", "")))
    return rows


def main():
    parser = argparse.ArgumentParser(description="本番の代表的なページを Lighthouse で測る")
    parser.add_argument("month", help="出力先の月（YYYY-MM）")
    parser.add_argument("paths", nargs="*", help="測るパス（省くと既定のページと単語詳細 1 枚）")
    args = parser.parse_args()
    if not re.fullmatch(r"\d{4}-\d{2}", args.month):
        parser.error("月は YYYY-MM で渡す")
    if not shutil.which("npx"):
        sys.exit("npx が無い（Node が要る）")
    chrome = chrome_path()

    paths = args.paths
    if not paths:
        word = first_word_path()
        paths = PAGES + ([word] if word else [])

    output_dir = os.path.join(OUTPUT_ROOT, args.month)
    report_dir = os.path.join(output_dir, "lighthouse")
    os.makedirs(report_dir, exist_ok=True)

    lines = [f"# Lighthouse（{time.strftime('%Y-%m-%d')}）", "",
             "スマホの条件（Lighthouse の既定。遅い回線と CPU を模す）で、1 枚につき 1 回測った値。回ごとに数点ぶれる。", "",
             "| ページ | " + " | ".join(CATEGORIES) + " |", "|---|" + "---|" * len(CATEGORIES)]
    details = []
    for index, path in enumerate(paths):
        if index:
            time.sleep(INTERVAL)
        print(f"{path} を測る", file=sys.stderr)
        result = measure(path, chrome, report_dir)
        if result is None:
            lines.append(f"| `{path}` | " + " | ".join(["測れなかった"] * len(CATEGORIES)) + " |")
            continue
        scores = [result["categories"][key]["score"] for key in CATEGORIES]
        lines.append(f"| `{path}` | " + " | ".join("—" if score is None else str(round(score * 100)) for score in scores) + " |")
        rows = findings(result)
        details += ["", f"## `{path}`", ""]
        details += [f"- {category}: {title}" + (f"（{value}）" if value else "") for category, title, value in rows] or ["満点でない項目は無い。"]
    lines += details + ["", f"報告書（HTML）は `{os.path.relpath(report_dir, ROOT)}/`。"]

    with open(os.path.join(output_dir, "lighthouse.md"), "w", encoding="utf-8") as file:
        file.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
