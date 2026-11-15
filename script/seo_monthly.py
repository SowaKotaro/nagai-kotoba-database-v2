# -*- coding: utf-8 -*-
"""Search Console のエクスポートを、月次の SEO の点検で使う決まった表にする道具。

手順と表の読み方の正は docs/seo-operations.md（§2 が入力、§3 が手順、§4 が判定）。
数えるのはこのスクリプトで、モデルは数えない（同じ入力なら、誰が回しても同じ数になる）。
標準ライブラリだけで動き、アプリにも DB にも触れない。本番へは公開語の写しを 1 回読むだけ（--jp-file で省ける）。

    python3 script/seo_monthly.py 2026-12

入力（gitignore 済み。置き方は docs/seo-operations.md §2）:
  research/inputs/seo/<月>/   Search Console のエクスポートを、zip を解いたフォルダのまま置く
                              （検索パフォーマンス・ページのインデックス登録・クロールの統計情報。GA4 の CSV は ga4-*.csv）
出力（gitignore 済み）:
  research/outputs/seo/<月>/report.md      表と警報（人とモデルが読む）
  research/outputs/seo/<月>/summary.json   同じ数（次の月との差を取る）
"""
import argparse
import collections
import csv
import glob
import json
import os
import re
import statistics
import sys
import unicodedata
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INPUT_ROOT = os.path.join(ROOT, "research", "inputs", "seo")
OUTPUT_ROOT = os.path.join(ROOT, "research", "outputs", "seo")
JP_HOST = "nagai-kotoba-database.jp"
COM_HOST = "nagai-kotoba-database.com"
JP_FULL_URL = f"https://{JP_HOST}/llms-full.txt"

# ページの型（切り口）。正規表現は docs/seo-plan.md §8 の表と同じで、上から順に当てる。
PAGE_TYPES = [
    ("単語詳細", re.compile(r"/words/[0-9]+$")),
    ("ファセット面", re.compile(r"/words\?")),
    ("ハブとホーム", re.compile(r"")),
]

# --- 判定の基準値（docs/seo-operations.md §4 が名前で指す。値の正はここ） ---
# 切り口の表示回数が 28 日でこれ未満のあいだは、施策の前後を比べない（観測だけにする）。1 日 10 回ほどに当たる。
MIN_IMPRESSIONS_TO_JUDGE = 300
# 検索の水準: .jp の表示回数が 1 日あたりこれ以上なら「戻った」（解禁直後の 2026-08 上旬が 1 日 100 回ほどだった。docs/seo-plan.md §12.1）。
RECOVERED_IMPRESSIONS_PER_DAY = 100
# 検索の水準: 1 日あたりこれ未満なら「戻っていない」。MIN_IMPRESSIONS_TO_JUDGE を 28 日で割った値と揃える。
LOW_IMPRESSIONS_PER_DAY = MIN_IMPRESSIONS_TO_JUDGE / 28
# 単語詳細の title に「読み方」などを足す案（B-3）を出す条件: 検索語の表の表示のうち、INTENT_WORDS を含む検索語の割合。
INTENT_SHARE_TO_PROPOSE = 0.20
# 「もう少しで 1 ページ目」の掲載順位の幅（docs/seo-plan.md §5 A-4）。
NEAR_FIRST_PAGE = (5.0, 15.0)
# 「表示が多いのにクリックが少ないページ」の条件: 表示回数がこれ以上で、CTR がこれ未満。
LOW_CTR_MIN_IMPRESSIONS = 20
LOW_CTR_MAX = 0.01
# 警報: 登録済みページ数が前の月からこの割合以上減った。
ALERT_INDEXED_DROP = 0.10
# 警報: 「noindex タグによって除外」が前の月からこの件数以上増えた（Issue 80 のシャッフルの URL は 3,186 件だった）。
ALERT_NOINDEX_RISE = 300
# 注意: Google が登録を見送ったページ（クロール済み未登録＋検出未登録）が前の月からこの割合以上増えた。
WARN_NOT_INDEXED_RISE = 0.20
# 注意: 1 日のクロールの最大が、期間の中央値のこの倍以上（Issue 80 の集中クロールは 925 件で、中央値の約 7 倍だった）。
WARN_CRAWL_SPIKE = 5.0
# 警報: クロールの応答に占めるサーバーエラー（5xx）の割合。
ALERT_SERVER_ERROR = 0.01
# 表に出す行数の上限。
TABLE_ROWS = 30
GA4_ROWS = 15

# 取りたい検索語（旧 .com が上位を持っていた語。docs/seo-plan.md §12.7）。空白の有無は同じ語として合算する。
TARGET_QUERIES = ["長い単語", "長い言葉", "長い単語 日本語", "日本語 長い単語", "日本一長い言葉", "一番長い日本語", "長い言葉 日本語"]
# 「10文字の言葉」の類（ファセット面の入口になる検索語）。
LENGTH_QUERY = re.compile(r"[0-9０-９]+\s*(文字|字|モーラ|拍)")
# 単語詳細の title に「読み方」などを足すか（docs/seo-plan.md §5 B-3）の材料にする、検索語の中の語。
INTENT_WORDS = ["読み方", "読み", "意味", "とは"]
# 個別の語ではない検索語の目印（「収録していない語」の候補から外す）。
GENERIC_WORDS = ["長い", "言葉", "単語", "文字", "日本語", "一番", "ランキング", "一覧", "データベース", "読み方", "意味", "とは"]

IGNORED = re.compile(r"[\s・=＝\-‐－―〜~!！?？、。,.「」『』()（）'’\"”“:：/／]")
HIRAGANA = {code: code + 0x60 for code in range(0x3041, 0x3097)}

REASON_NOINDEX = "noindex タグによって除外されました"
REASON_CRAWLED = "クロール済み - インデックス未登録"
REASON_DISCOVERED = "検出 - インデックス未登録"


def loose(text):
    """表記ゆれ（全角半角・大文字小文字・かなの種類・空白と記号）を畳む。"""
    return IGNORED.sub("", unicodedata.normalize("NFKC", text)).lower().translate(HIRAGANA)


def number(text):
    text = (text or "").replace(",", "").replace("%", "").strip()
    return float(text) if text else 0.0


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as file:
        rows = [row for row in csv.reader(file) if row]
    return (rows[0], rows[1:]) if rows else ([], [])


def read_export(directory):
    """1 つのエクスポート（zip を解いたフォルダ）を、表の種類ごとに読む。ファイル名ではなく見出しの 1 列目で見分ける。"""
    tables = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.csv"))):
        header, rows = read_csv(path)
        if not header:
            continue
        first = header[0]
        if first == "日付":
            if "登録済み" in header:
                first = "日付:登録"
            elif any("クロール" in column for column in header):
                first = "日付:クロール"
            else:
                first = "日付:検索"
        if first == "理由":
            tables.setdefault("理由", ([], []))[1].extend(rows)
            continue
        tables[first] = (header, rows)
    return tables


def read_ga4(path):
    """GA4 のレポートの CSV（先頭に # の注記、そのあとに表）から、注記と最初の表を読む。"""
    notes, header, rows = [], None, []
    with open(path, encoding="utf-8-sig", newline="") as file:
        for line in file:
            line = line.rstrip("\r\n")
            if line.startswith("#"):
                if header:
                    break
                notes.append(line.lstrip("# ").strip())
            elif not line.strip():
                if header:
                    break
            elif header is None:
                header = next(csv.reader([line]))
            else:
                rows.append(next(csv.reader([line])))
    notes = [note for note in notes if note and not set(note) <= {"-"}]
    return {"file": os.path.basename(path), "notes": notes, "header": header or [], "rows": rows}


def find_exports(month_dir):
    """月のフォルダの下から、エクスポートを種類ごとに集める。"""
    performance, coverage, crawl, url_lists = [], [], [], []
    for directory, _subdirs, files in sorted(os.walk(month_dir)):
        if not any(name.endswith(".csv") for name in files):
            continue
        tables = read_export(directory)
        name = os.path.basename(directory)
        if "上位のページ" in tables or "上位のクエリ" in tables:
            performance.append((name, tables))
        elif "URL" in tables:
            url_lists.append((name, tables))
        elif "日付:登録" in tables or "理由" in tables:
            coverage.append((name, tables))
        elif "日付:クロール" in tables:
            crawl.append((name, tables))
    return performance, coverage, crawl, url_lists


def host_of(name, tables):
    """エクスポートがどのプロパティのものか。ページの URL があればそれで、無ければフォルダ名で決める。"""
    _header, pages = tables.get("上位のページ", ([], []))
    probe = pages[0][0] if pages else name
    return COM_HOST if COM_HOST in probe else JP_HOST


def page_type(url):
    parsed = urllib.parse.urlsplit(url)
    target = parsed.path + ("?" + parsed.query if parsed.query else "")
    return next(label for label, pattern in PAGE_TYPES if pattern.search(target))


def weighted_position(rows):
    impressions = sum(row["impressions"] for row in rows)
    if not impressions:
        return None
    return sum(row["position"] * row["impressions"] for row in rows) / impressions


def metric_rows(table):
    _header, rows = table
    return [
        {"key": row[0], "clicks": number(row[1]), "impressions": number(row[2]), "position": number(row[4])}
        for row in rows if len(row) >= 5
    ]


def summarize_performance(tables):
    dates = metric_rows(tables.get("日付:検索", ([], [])))
    devices = metric_rows(tables.get("デバイス", ([], [])))
    pages = metric_rows(tables.get("上位のページ", ([], [])))
    queries = metric_rows(tables.get("上位のクエリ", ([], [])))
    filters = dict(row[:2] for row in tables.get("フィルタ", ([], []))[1] if len(row) >= 2)
    # 合計はデバイスの表の和にする（ページの表と検索語の表は、同じ表示を複数の行に数えたり、匿名の検索語を落としたりする）。
    total_source = devices or dates
    summary = {
        "filters": filters,
        "period_start": dates[0]["key"] if dates else None,
        "period_end": dates[-1]["key"] if dates else None,
        "days": len(dates),
        "impressions": sum(row["impressions"] for row in total_source),
        "clicks": sum(row["clicks"] for row in total_source),
        "position": weighted_position(total_source),
        "by_type": {},
        "facet_keys": {},
    }
    summary["impressions_per_day"] = summary["impressions"] / summary["days"] if summary["days"] else None
    summary["clicks_per_day"] = summary["clicks"] / summary["days"] if summary["days"] else None
    for label, _pattern in PAGE_TYPES:
        of_type = [row for row in pages if page_type(row["key"]) == label]
        summary["by_type"][label] = {
            "pages": len(of_type),
            "impressions": sum(row["impressions"] for row in of_type),
            "clicks": sum(row["clicks"] for row in of_type),
            "position": weighted_position(of_type),
        }
    facet_keys = collections.Counter()
    for row in pages:
        if page_type(row["key"]) == "ファセット面":
            for key in urllib.parse.parse_qs(urllib.parse.urlsplit(row["key"]).query):
                facet_keys[key] += 1
    summary["facet_keys"] = dict(facet_keys.most_common())
    return summary, dates, pages, queries


def summarize_coverage(tables):
    _header, chart = tables.get("日付:登録", ([], []))
    metadata = dict(row[:2] for row in tables.get("プロパティ", ([], []))[1] if len(row) >= 2)
    reasons = {row[0]: int(number(row[3])) for row in tables.get("理由", ([], []))[1] if len(row) >= 4}
    last = chart[-1] if chart else None
    return {
        "sitemap": metadata.get("サイトマップ", "（不明）"),
        "date": last[0] if last else None,
        "not_indexed": int(number(last[1])) if last else None,
        "indexed": int(number(last[2])) if last else None,
        "reasons": reasons,
    }


def summarize_crawl(tables):
    _header, chart = tables.get("日付:クロール", ([], []))
    requests = [(row[0], int(number(row[1]))) for row in chart if len(row) >= 2]
    counts = [count for _date, count in requests]
    ratios = lambda name: {row[0]: number(row[1]) for row in tables.get(name, ([], []))[1] if len(row) >= 2}
    responses = ratios("レスポンス")
    peak = max(requests, key=lambda item: item[1]) if requests else (None, 0)
    return {
        "period_start": requests[0][0] if requests else None,
        "period_end": requests[-1][0] if requests else None,
        "days": len(requests),
        "total": sum(counts),
        "per_day": sum(counts) / len(counts) if counts else None,
        "median": statistics.median(counts) if counts else None,
        "peak_date": peak[0],
        "peak": peak[1],
        "responses": responses,
        "server_error": sum(ratio for name, ratio in responses.items() if "5xx" in name or "サーバー エラー" in name),
        "purposes": ratios("目的"),
    }


def read_jp_forms(text):
    """公開語の写し（llms-full.txt）から、表層形・別表記・読みを畳んだ形で集める。"""
    forms = set()
    for line in text.splitlines():
        if line.startswith("### "):
            forms.add(loose(line[4:]))
        elif line.startswith("- 読み: "):
            forms.add(loose(re.sub(r"\(\d+字.*$", "", line[6:])))
        elif line.startswith("- 別表記: "):
            for item in line[7:].split("、"):
                matched = re.match(r"(.*)\(([^()]*)\)$", item.strip())
                forms.update(loose(part) for part in (matched.groups() if matched else (item.strip(),)))
    forms.discard("")
    return forms


def load_jp_forms(args):
    if args.no_corpus:
        return None
    if args.jp_file:
        with open(args.jp_file, encoding="utf-8") as file:
            return read_jp_forms(file.read())
    request = urllib.request.Request(JP_FULL_URL, headers={"User-Agent": "seo-monthly"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return read_jp_forms(response.read().decode("utf-8"))
    except OSError as error:
        print(f"公開語の写しを取得できなかった（{error}）。「収録していない語」の表は省く", file=sys.stderr)
        return None


def unlisted_queries(queries, forms):
    """公開語のどれとも重ならない検索語（収録の候補）。一般的な検索語は外す。"""
    found = []
    for row in queries:
        if any(word in row["key"] for word in GENERIC_WORDS):
            continue
        folded = loose(row["key"])
        if len(folded) < 4:
            continue
        if any(folded in form or form in folded for form in forms):
            continue
        found.append(row)
    return sorted(found, key=lambda row: -row["impressions"])


# --- 出力 ---

def fmt(value, digits=0):
    if value is None:
        return "—"
    if digits:
        return f"{value:,.{digits}f}"
    return f"{int(round(value)):,}"


def delta(now, before, digits=0):
    if now is None or before is None:
        return "—"
    difference = now - before
    sign = "+" if difference > 0 else ("±" if difference == 0 else "−")
    return f"{sign}{fmt(abs(difference), digits)}"


def table(header, rows):
    if not rows:
        return ["（該当なし）", ""]
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(str(cell).replace("|", "\\|") for cell in row) + " |" for row in rows]
    return lines + [""]


def short(key):
    """ページの URL は、ホストを落として読める字に戻す（検索語はそのまま）。"""
    if not key.startswith("http"):
        return key
    parsed = urllib.parse.urlsplit(key)
    return urllib.parse.unquote(parsed.path + ("?" + parsed.query if parsed.query else ""))


def metric_table(label, rows, limit=TABLE_ROWS):
    body = [
        (short(row["key"]), fmt(row["impressions"]), fmt(row["clicks"]), fmt(row["position"], 1))
        for row in rows[:limit]
    ]
    lines = table([label, "表示回数", "クリック数", "掲載順位"], body)
    if len(rows) > limit:
        lines.insert(-1, f"（ほか {len(rows) - limit} 行。表示回数の多い順に {limit} 行まで）")
    return lines


def analyze(month_dir, forms=None):
    """1 か月分を集計する。返すのは (summary, report の材料)。"""
    performance, coverage, crawl, url_lists = find_exports(month_dir)
    summary = {"jp": None, "com": None, "coverage": [], "crawl": None, "url_lists": []}
    detail = {}
    for name, tables in performance:
        result = summarize_performance(tables)
        if host_of(name, tables) == COM_HOST:
            summary["com"] = result[0]
        else:
            summary["jp"], detail["dates"], detail["pages"], detail["queries"] = result
    for name, tables in coverage:
        if COM_HOST in name:
            continue
        summary["coverage"].append(summarize_coverage(tables))
    for name, tables in crawl:
        if COM_HOST not in name:
            summary["crawl"] = summarize_crawl(tables)
    for name, tables in url_lists:
        urls = [row[0] for row in tables["URL"][1] if row]
        metadata = dict(row[:2] for row in tables.get("プロパティ", ([], []))[1] if len(row) >= 2)
        facets = collections.Counter(key for url in urls if page_type(url) == "ファセット面"
                                     for key in urllib.parse.parse_qs(urllib.parse.urlsplit(url).query))
        summary["url_lists"].append({
            "name": name, "metadata": metadata, "urls": len(urls),
            "by_type": dict(collections.Counter(page_type(url) for url in urls)), "facet_keys": dict(facets.most_common()),
        })
    detail["forms"] = forms
    detail["ga4"] = [read_ga4(path) for path in sorted(glob.glob(os.path.join(month_dir, "ga4*.csv")))]
    return summary, detail


def coverage_all(summary):
    """「すべての既知のページ」の登録状況（サイトマップで絞っていないエクスポート）。"""
    for item in summary["coverage"]:
        if "すべての既知" in item["sitemap"]:
            return item
    return None


def level(jp):
    """検索の水準（docs/seo-operations.md §4.2）。"""
    per_day = jp["impressions_per_day"] or 0
    if per_day >= RECOVERED_IMPRESSIONS_PER_DAY:
        return "戻った"
    return "戻っていない" if per_day < LOW_IMPRESSIONS_PER_DAY else "途中"


def alerts(summary, previous):
    found = []
    jp = summary["jp"]
    if jp:
        scale = 28 / jp["days"] if jp["days"] else 1
        for label, values in jp["by_type"].items():
            if values["impressions"] * scale < MIN_IMPRESSIONS_TO_JUDGE:
                found.append(("観測のみ", f"{label}の表示回数が 28 日あたり {fmt(values['impressions'] * scale)} で、"
                              f"基準 {MIN_IMPRESSIONS_TO_JUDGE} に届かない。この切り口の施策は、前後を比べない"))
    crawl = summary["crawl"]
    if crawl:
        if crawl["median"] and crawl["peak"] >= crawl["median"] * WARN_CRAWL_SPIKE:
            found.append(("注意", f"クロールが {crawl['peak_date']} に {fmt(crawl['peak'])} 件（中央値 {fmt(crawl['median'])} の "
                          f"{crawl['peak'] / crawl['median']:.1f} 倍）。URL が増えていないかを確かめる"))
        if crawl["server_error"] >= ALERT_SERVER_ERROR:
            found.append(("警報", f"クロールの応答の {crawl['server_error']:.2%} がサーバーエラー"))
    now, before = coverage_all(summary), coverage_all(previous) if previous else None
    if now and before:
        if before["indexed"] and now["indexed"] <= before["indexed"] * (1 - ALERT_INDEXED_DROP):
            found.append(("警報", f"登録済みが {fmt(before['indexed'])} → {fmt(now['indexed'])} に減った"))
        noindex_rise = now["reasons"].get(REASON_NOINDEX, 0) - before["reasons"].get(REASON_NOINDEX, 0)
        if noindex_rise >= ALERT_NOINDEX_RISE:
            found.append(("警報", f"noindex による除外が {fmt(noindex_rise)} 件増えた。noindex の URL が湧いていないかを確かめる"))
        skipped = lambda item: item["reasons"].get(REASON_CRAWLED, 0) + item["reasons"].get(REASON_DISCOVERED, 0)
        if skipped(before) and skipped(now) >= skipped(before) * (1 + WARN_NOT_INDEXED_RISE):
            found.append(("注意", f"登録を見送られたページ（クロール済み未登録＋検出未登録）が {fmt(skipped(before))} → {fmt(skipped(now))} に増えた"))
    return found


def build_report(month, summary, detail, previous, previous_month):
    lines = [f"# SEO の月次の集計（{month}）", "",
             "script/seo_monthly.py が作る。読み方と判定は docs/seo-operations.md §4。数字はすべてエクスポートのもの。", ""]
    jp, prev_jp = summary["jp"], (previous or {}).get("jp")

    lines += ["## 0. 警報", ""]
    found = alerts(summary, previous)
    lines += table(["種別", "内容"], found) if found else ["無し", ""]

    lines += ["## 1. 検索パフォーマンス（.jp）", ""]
    if not jp:
        lines += ["検索パフォーマンスのエクスポートが無い。", ""]
    else:
        lines += [f"- **検索の水準: {level(jp)}**（表示 1 日あたり {fmt(jp['impressions_per_day'], 1)} 回。"
                  f"{RECOVERED_IMPRESSIONS_PER_DAY} 以上で「戻った」、{LOW_IMPRESSIONS_PER_DAY:.1f} 未満で「戻っていない」）",
                  f"- 期間: {jp['period_start']} 〜 {jp['period_end']}（{jp['days']} 日）。"
                  f"絞り込み: {'、'.join(f'{key}={value}' for key, value in jp['filters'].items()) or '（記録なし）'}"]
        if prev_jp:
            lines += [f"- 比べる相手: {previous_month}（{prev_jp['period_start']} 〜 {prev_jp['period_end']}、{prev_jp['days']} 日）。"
                      "日数が違うときは、合計ではなく 1 日あたりで比べる"]
        lines += [""]
        rows = [
            ("表示回数", fmt(jp["impressions"]), fmt(jp["impressions_per_day"], 1),
             delta(jp["impressions_per_day"], prev_jp and prev_jp["impressions_per_day"], 1)),
            ("クリック数", fmt(jp["clicks"]), fmt(jp["clicks_per_day"], 2),
             delta(jp["clicks_per_day"], prev_jp and prev_jp["clicks_per_day"], 2)),
            ("平均掲載順位（表示回数で加重）", fmt(jp["position"], 1), "—", delta(jp["position"], prev_jp and prev_jp["position"], 1)),
        ]
        lines += table(["", "合計", "1 日あたり", "前の月との差（1 日あたり・順位）"], rows)

        lines += ["### 1.1 切り口ごと", ""]
        rows = []
        for label, values in jp["by_type"].items():
            before = prev_jp["by_type"][label] if prev_jp else None
            per_day = values["impressions"] / jp["days"] if jp["days"] else None
            before_per_day = before["impressions"] / prev_jp["days"] if before and prev_jp["days"] else None
            rows.append((label, fmt(values["pages"]), fmt(values["impressions"]), fmt(values["clicks"]), fmt(values["position"], 1),
                         fmt(per_day, 1), delta(per_day, before_per_day, 1), delta(values["position"], before and before["position"], 1)))
        lines += table(["切り口", "表示があったページ", "表示回数", "クリック数", "平均掲載順位", "表示/日", "表示/日の差", "順位の差"], rows)
        lines += ["ファセット面の内訳（表示があった面の数）: "
                  + ("、".join(f"`{key}` {count}" for key, count in jp["facet_keys"].items()) or "無し"), ""]

        dates = detail["dates"]
        lines += ["### 1.2 週ごと（期間の末尾から 7 日ずつ）", ""]
        weeks = []
        for end in range(len(dates), 0, -7):
            chunk = dates[max(0, end - 7):end]
            weeks.append((f"{chunk[0]['key']} 〜 {chunk[-1]['key']}", len(chunk),
                          fmt(sum(row["impressions"] for row in chunk)), fmt(sum(row["clicks"] for row in chunk))))
        lines += table(["週", "日数", "表示回数", "クリック数"], list(reversed(weeks)))

        queries, pages = detail["queries"], detail["pages"]
        low, high = NEAR_FIRST_PAGE
        lines += ["### 1.3 取りたい検索語", ""]
        rows = []
        for target in TARGET_QUERIES:
            matched = [row for row in queries if loose(row["key"]) == loose(target)]
            rows.append((target, fmt(sum(row["impressions"] for row in matched)) if matched else "表示なし",
                         fmt(sum(row["clicks"] for row in matched)) if matched else "—", fmt(weighted_position(matched), 1)))
        lines += table(["検索語", "表示回数", "クリック数", "掲載順位"], rows)
        length_queries = sorted((row for row in queries if LENGTH_QUERY.search(row["key"])), key=lambda row: -row["impressions"])
        lines += [f"「◯文字の言葉」の類: {len(length_queries)} 語、表示 {fmt(sum(row['impressions'] for row in length_queries))}、"
                  f"平均掲載順位 {fmt(weighted_position(length_queries), 1)}", ""]
        lines += metric_table("検索語", length_queries, 10)

        lines += [f"### 1.4 表 A: 掲載順位 {low:g}〜{high:g} 位の検索語とページ", ""]
        near = lambda rows: sorted((row for row in rows if low <= row["position"] <= high), key=lambda row: -row["impressions"])
        lines += metric_table("検索語", near(queries)) + metric_table("ページ", near(pages))
        lines += ["エクスポートは検索語とページを別々の表で出すので、「どの検索語でどのページが出たか」の組は分からない"
                  "（要るときは、Search Console の画面でページを絞り込む）。", ""]

        lines += [f"### 1.5 表 B: 表示が {LOW_CTR_MIN_IMPRESSIONS} 回以上で、CTR が {LOW_CTR_MAX:.0%} 未満のページ", ""]
        low_ctr = sorted((row for row in pages if row["impressions"] >= LOW_CTR_MIN_IMPRESSIONS
                          and row["clicks"] / row["impressions"] < LOW_CTR_MAX), key=lambda row: -row["impressions"])
        lines += metric_table("ページ", low_ctr)

        lines += ["### 1.6 表 C: 公開語のどれとも重ならない検索語（収録の候補）", ""]
        if detail["forms"] is None:
            lines += ["公開語の写しを読んでいないので省いた。", ""]
        else:
            lines += metric_table("検索語", unlisted_queries(queries, detail["forms"]))

        lines += ["### 1.7 検索語に含まれる語（B-3 の材料）", ""]
        listed = sum(row["impressions"] for row in queries)
        rows = []
        for word in INTENT_WORDS:
            matched = [row for row in queries if word in row["key"]]
            impressions = sum(row["impressions"] for row in matched)
            rows.append((word, len(matched), fmt(impressions), f"{impressions / listed:.1%}" if listed else "—"))
        lines += table(["語", "検索語の数", "表示回数", "検索語の表の表示に占める割合"], rows)
        any_intent = sum(row["impressions"] for row in queries if any(word in row["key"] for word in INTENT_WORDS))
        share = any_intent / listed if listed else 0
        lines += [f"どれかを含む検索語の表示は {fmt(any_intent)} 回で、検索語の表の {share:.1%}"
                  f"（B-3 を提案する条件は {INTENT_SHARE_TO_PROPOSE:.0%} 以上。いまは{'満たす' if share >= INTENT_SHARE_TO_PROPOSE else '満たさない'}）。", ""]

    lines += ["## 2. インデックス登録（.jp）", ""]
    if not summary["coverage"]:
        lines += ["ページのインデックス登録のエクスポートが無い。", ""]
    for item in summary["coverage"]:
        before = next((other for other in (previous or {}).get("coverage", []) if other["sitemap"] == item["sitemap"]), None)
        lines += [f"### {item['sitemap']}（{item['date']} 時点）", ""]
        rows = [("登録済み", fmt(item["indexed"]), delta(item["indexed"], before and before["indexed"])),
                ("未登録", fmt(item["not_indexed"]), delta(item["not_indexed"], before and before["not_indexed"]))]
        rows += [(f"未登録の理由: {reason}", fmt(count), delta(count, before and before["reasons"].get(reason, 0)))
                 for reason, count in sorted(item["reasons"].items(), key=lambda pair: -pair[1])]
        lines += table(["状態", "ページ数", "前の月との差"], rows)

    if summary["url_lists"]:
        lines += ["### 理由ごとの URL の一覧（エクスポートは 1,000 行まで）", ""]
        rows = [(item["name"], "、".join(f"{key}={value}" for key, value in item["metadata"].items()) or "—", fmt(item["urls"]),
                 "、".join(f"{label} {count}" for label, count in item["by_type"].items()),
                 "、".join(f"`{key}` {count}" for key, count in item["facet_keys"].items()) or "—") for item in summary["url_lists"]]
        lines += table(["フォルダ", "メタデータ", "URL の数", "切り口ごと", "ファセット面の内訳"], rows)

    lines += ["## 3. クロールの統計情報（.jp）", ""]
    crawl = summary["crawl"]
    if not crawl:
        lines += ["クロールの統計情報のエクスポートが無い。", ""]
    else:
        lines += [f"- 期間: {crawl['period_start']} 〜 {crawl['period_end']}（{crawl['days']} 日）",
                  f"- 合計 {fmt(crawl['total'])} 件、1 日あたり {fmt(crawl['per_day'], 1)} 件、中央値 {fmt(crawl['median'])} 件、"
                  f"最大 {fmt(crawl['peak'])} 件（{crawl['peak_date']}）",
                  "- 応答: " + "、".join(f"{name} {ratio:.2%}" for name, ratio in crawl["responses"].items()),
                  "- 目的: " + "、".join(f"{name} {ratio:.1%}" for name, ratio in crawl["purposes"].items()), ""]

    lines += ["## 4. 旧 .com の検索パフォーマンス", ""]
    com, prev_com = summary["com"], (previous or {}).get("com")
    if not com:
        lines += ["エクスポートが無い（任意）。", ""]
    else:
        lines += [f"- 期間: {com['period_start']} 〜 {com['period_end']}（{com['days']} 日）",
                  f"- 表示 {fmt(com['impressions'])}（1 日あたり {fmt(com['impressions_per_day'], 1)}、"
                  f"前の月との差 {delta(com['impressions_per_day'], prev_com and prev_com['impressions_per_day'], 1)}）、"
                  f"クリック {fmt(com['clicks'])}、平均掲載順位 {fmt(com['position'], 1)}", ""]

    lines += ["## 5. GA4", ""]
    if not detail["ga4"]:
        lines += ["CSV が無い（任意。置くなら ga4-*.csv）。", ""]
    for report in detail["ga4"]:
        header = report["header"]
        sessions = header.index("セッション") if "セッション" in header else (1 if len(header) > 1 else 0)
        lines += [f"### {report['file']}", "", "- " + " / ".join(report["notes"]), ""]
        lines += table([header[0], header[sessions]], [(row[0], row[sessions]) for row in report["rows"][:GA4_ROWS] if len(row) > sessions])

    lines += ["## 6. docs/seo-log.md に足す行", "", "表 1（検索）:", ""]
    if jp:
        cell = lambda label: f"{fmt(jp['by_type'][label]['impressions'])}・{fmt(jp['by_type'][label]['position'], 1)}"
        lines += ["```", f"| {month} | {jp['period_start']}〜{jp['period_end']} | {jp['days']} | {fmt(jp['impressions'])} | {fmt(jp['clicks'])} | "
                  f"{fmt(jp['impressions_per_day'], 1)} | {cell('単語詳細')} | {cell('ファセット面')} | {cell('ハブとホーム')} | "
                  f"{fmt(com['impressions_per_day'], 1) if com else '—'} |", "```", ""]
    lines += ["表 2（登録とクロール）:", ""]
    everything = coverage_all(summary)
    by_sitemap = lambda needle: next((f"{fmt(item['indexed'])} / {fmt(item['not_indexed'])}" for item in summary["coverage"]
                                      if needle in item["sitemap"]), "—")
    if everything:
        reasons = everything["reasons"]
        lines += ["```", f"| {month} | {fmt(everything['indexed'])} | {fmt(everything['not_indexed'])} | {fmt(reasons.get(REASON_CRAWLED, 0))} | "
                  f"{fmt(reasons.get(REASON_DISCOVERED, 0))} | {fmt(reasons.get(REASON_NOINDEX, 0))} | {by_sitemap('/sitemap.xml')} | "
                  f"{by_sitemap('sitemap-facets.xml')} | {fmt(crawl['per_day'], 1) if crawl else '—'} |", "```", ""]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("month", help="月のフォルダ名（YYYY-MM）")
    parser.add_argument("--jp-file", help="保存済みの llms-full.txt（省くと本番から 1 回だけ取得する）")
    parser.add_argument("--no-corpus", action="store_true", help="公開語の写しを読まない（「収録していない語」の表を省く）")
    args = parser.parse_args()

    month_dir = os.path.join(INPUT_ROOT, args.month)
    if not os.path.isdir(month_dir):
        sys.exit(f"{month_dir} が無い（エクスポートの置き方は docs/seo-operations.md §2）")
    summary, detail = analyze(month_dir, load_jp_forms(args))
    if not summary["jp"] and not summary["coverage"]:
        sys.exit(f"{month_dir} に Search Console のエクスポートが見つからない（表示言語が日本語のエクスポートだけを読める）")

    earlier = sorted(name for name in os.listdir(INPUT_ROOT)
                     if name < args.month and os.path.isdir(os.path.join(INPUT_ROOT, name)))
    previous_month = earlier[-1] if earlier else None
    previous = analyze(os.path.join(INPUT_ROOT, previous_month))[0] if previous_month else None

    output_dir = os.path.join(OUTPUT_ROOT, args.month)
    os.makedirs(output_dir, exist_ok=True)
    report = build_report(args.month, summary, detail, previous, previous_month)
    with open(os.path.join(output_dir, "report.md"), "w", encoding="utf-8") as file:
        file.write(report)
    with open(os.path.join(output_dir, "summary.json"), "w", encoding="utf-8") as file:
        json.dump(summary, file, ensure_ascii=False, indent=2)
    print(report)
    print(f"書き出した: {os.path.join(output_dir, 'report.md')}", file=sys.stderr)


if __name__ == "__main__":
    main()
