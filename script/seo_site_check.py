# -*- coding: utf-8 -*-
"""本番の公開ページを読み取りだけで巡回し、検索エンジンから見える形が規則どおりかを確かめる道具（月次の SEO の点検）。

テストが守るのはコードの挙動で、本番の実際（Cloudflare を通ったあとの応答、sitemap の中身、ハブからのリンク）は見ていない。
手順の正は docs/seo-operations.md §3、見ているものの一覧は同 §5。規則の正はコード（docs/seo-plan.md §4.2 に場所）。
標準ライブラリだけで動き、アプリにも DB にも触れない。本番へは GET を 1 秒に 1 件ほど、あわせて 40 件ほど送る。

    python3 script/seo_site_check.py 2026-12

出力（gitignore 済み）:
  research/outputs/seo/<月>/site-check.md     数と、1 行 1 問題の表（問題が無ければ「無し」）
  research/outputs/seo/<月>/site-check.json   同じ数（次の月との差を取る）
"""
import argparse
import collections
import html.parser
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_ROOT = os.path.join(ROOT, "research", "outputs", "seo")
JP_HOST = "nagai-kotoba-database.jp"
COM_HOST = "nagai-kotoba-database.com"
USER_AGENT = "seo-site-check"
INTERVAL = 1.0        # 取得の間隔（秒）。Puma は 1 プロセスなので詰めない
HEAVY_INTERVAL = 3.0  # 重い応答（sitemap・/stats）の前後に空ける間隔（秒）

# インデックスさせているページ（sitemap.xml の静的ページと同じ顔ぶれ。ここからファセット面へのリンクも集める）。
HUBS = ["/", "/words", "/genres", "/entity_types", "/linguistic_features", "/browse", "/rankings", "/stats", "/about", "/privacy"]
HEAVY = {"/stats"}
# 単語詳細を、sitemap の並びから等間隔に何枚見るか。
WORD_SAMPLES = 5
# noindex でなければならない URL（URL の空間を閉じている規則。docs/seo-plan.md §4.2、changelog の Issue 80・81）。
MUST_NOINDEX = [
    ("2 ページ目", "/words?page=2"),
    ("範囲外のページ", "/words?page=9999"),
    ("既定でない並び", "/words?sort=length_desc"),
    ("シャッフル", "/words?sort=shuffle"),
    ("0 件のファセット面", "/words?reading_length=99"),
    ("条件が 2 つ", "/words?reading_length=10&mora_count=10"),
    ("検索フォーム", "/search"),
]
# 404 でなければならない URL（実在しないマスタ id）。
MUST_404 = [("実在しないジャンル", "/words?genre_id=999999999"), ("実在しないエンティティ", "/words?entity_type_id=999999999")]
# 301 でなければならない URL と、行き先の先頭。
MUST_REDIRECT = [
    ("旧 .com のホーム", f"https://{COM_HOST}/", f"https://{JP_HOST}/"),
    ("旧 .com の一覧", f"https://{COM_HOST}/words", f"https://{JP_HOST}/words"),
    ("旧 .com の単語詳細", f"https://{COM_HOST}/words/1", f"https://{JP_HOST}/words"),
    ("www", f"https://www.{JP_HOST}/words", f"https://{JP_HOST}/words"),
    ("http", f"http://{JP_HOST}/words", f"https://{JP_HOST}/words"),
]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


FOLLOW = urllib.request.build_opener()
NO_FOLLOW = urllib.request.build_opener(NoRedirect)
last_request = [0.0]


def fetch(url, follow=True, pause=INTERVAL):
    """GET して (ステータス, ヘッダー, 本文, 最後の URL) を返す。つながらなければステータスは 0。"""
    wait = last_request[0] + pause - time.monotonic()
    if wait > 0:
        time.sleep(wait)
    parts = urllib.parse.urlsplit(url)
    safe = urllib.parse.urlunsplit(parts._replace(path=urllib.parse.quote(parts.path, safe="/%"),
                                                  query=urllib.parse.quote(parts.query, safe="=&%[]")))
    request = urllib.request.Request(safe, headers={"User-Agent": USER_AGENT})
    try:
        with (FOLLOW if follow else NO_FOLLOW).open(request, timeout=60) as response:
            result = response.status, response.headers, response.read().decode("utf-8", "replace"), response.url
    except urllib.error.HTTPError as error:
        result = error.code, error.headers, "", url
    except OSError as error:
        result = 0, {}, str(error), url
    last_request[0] = time.monotonic()
    return result


class Page(html.parser.HTMLParser):
    """検索エンジンが読む要素だけを拾う。"""

    def __init__(self, text):
        super().__init__()
        self.title, self.description, self.robots, self.canonical = "", None, "", None
        self.h1, self.links, self.json_ld = 0, [], []
        self._in_title, self._in_json, self._title_done = False, False, False
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "title":
            self._in_title = not self._title_done  # 2 つ目からは図（SVG）の中の title なので読まない
        elif tag == "h1":
            self.h1 += 1
        elif tag == "meta" and attrs.get("name") == "description":
            self.description = attrs.get("content") or ""
        elif tag == "meta" and attrs.get("name") == "robots":
            self.robots = attrs.get("content") or ""
        elif tag == "link" and attrs.get("rel") == "canonical":
            self.canonical = attrs.get("href")
        elif tag == "a" and attrs.get("href"):
            self.links.append(attrs["href"])
        elif tag == "script" and attrs.get("type") == "application/ld+json":
            self._in_json = True
            self.json_ld.append("")

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title, self._title_done = False, True
        elif tag == "script":
            self._in_json = False

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        elif self._in_json:
            self.json_ld[-1] += data


def same_url(left, right):
    normalize = lambda url: urllib.parse.unquote(url or "").rstrip("/")
    return normalize(left) == normalize(right)


def noindex(page, headers):
    return "noindex" in page.robots.lower() or "noindex" in (headers.get("X-Robots-Tag") or "").lower()


def facet_of(url):
    """単一の条件の一覧（/words?key=value）なら (key, value)。それ以外は None。"""
    parts = urllib.parse.urlsplit(url)
    if parts.path != "/words":
        return None
    pairs = urllib.parse.parse_qsl(parts.query)
    if len(pairs) != 1:
        return None
    key, value = pairs[0]
    return key.removesuffix("[]"), value


def locs(text):
    return [urllib.parse.unquote(loc.replace("&amp;", "&")) for loc in re.findall(r"<loc>([^<]+)</loc>", text)]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("month", help="出力先の月（YYYY-MM）")
    args = parser.parse_args()
    base = f"https://{JP_HOST}"
    problems, checked = [], []

    def problem(kind, url, text):
        problems.append((kind, url.replace(base, "") or "/", text))

    # 1. robots.txt
    status, _headers, robots, _final = fetch(base + "/robots.txt")
    sitemap_lines = re.findall(r"(?im)^sitemap:\s*(\S+)", robots)
    disallows = re.findall(r"(?im)^disallow:\s*(\S*)", robots)
    if status != 200:
        problem("robots.txt", base + "/robots.txt", f"ステータスが {status}")
    for name in ("/sitemap.xml", "/sitemap-facets.xml"):
        if base + name not in sitemap_lines:
            problem("robots.txt", base + "/robots.txt", f"Sitemap の行に {name} が無い")
    for path in disallows:
        if path in ("", "/") or path.startswith("/words"):
            problem("robots.txt", base + "/robots.txt", f"公開ページを Disallow している（{path or '空'}）")

    # 2. サイトマップ
    status, _headers, text, _final = fetch(base + "/sitemap.xml", pause=HEAVY_INTERVAL)
    sitemap_urls = locs(text)
    if status != 200 or not sitemap_urls:
        problem("サイトマップ", base + "/sitemap.xml", f"ステータスが {status}、URL が {len(sitemap_urls)} 件")
    word_urls = [url for url in sitemap_urls if re.search(r"/words/[0-9]+$", url)]
    static_urls = [url for url in sitemap_urls if url not in set(word_urls)]
    status, _headers, text, _final = fetch(base + "/sitemap-facets.xml", pause=HEAVY_INTERVAL)
    facet_urls = locs(text)
    if status != 200 or not facet_urls:
        problem("サイトマップ", base + "/sitemap-facets.xml", f"ステータスが {status}、URL が {len(facet_urls)} 件")
    sitemap_facets = {facet_of(url) for url in facet_urls}
    if None in sitemap_facets:
        problem("サイトマップ", base + "/sitemap-facets.xml", "単一の条件の一覧ではない URL が載っている")
        sitemap_facets.discard(None)
    facet_keys = sorted({key for key, _value in sitemap_facets})
    for url in sitemap_urls + facet_urls:
        if not url.startswith(base + "/"):
            problem("サイトマップ", url, "canonical のホストではない URL が載っている")
            break

    # 3. インデックスさせるページ（ハブ・ホーム・静的ページ、単語詳細の見本、ファセット面の見本）
    step = max(1, (len(word_urls) - 1) // (WORD_SAMPLES - 1)) if word_urls else 1
    word_samples = word_urls[::step][:WORD_SAMPLES]
    facet_samples = []
    for key in facet_keys:  # 面の種類ごとに 1 面（値の並びの先頭）
        facet_samples.append(next(url for url in facet_urls if (facet_of(url) or ("", ""))[0] == key))
    targets = [("ハブ・静的", base + (path if path != "/" else "/")) for path in HUBS]
    targets += [("単語詳細", url) for url in word_samples] + [("ファセット面", url) for url in facet_samples]

    hub_facets = set()
    for kind, url in targets:
        path = url.replace(base, "")
        status, headers, text, _final = fetch(url, pause=HEAVY_INTERVAL if path in HEAVY else INTERVAL)
        if status != 200:
            problem(kind, url, f"ステータスが {status}")
            continue
        page = Page(text)
        checked.append({"kind": kind, "url": url, "title": page.title.strip(), "description": page.description})
        if noindex(page, headers):
            problem(kind, url, "noindex が付いている")
        if not page.title.strip():
            problem(kind, url, "title が空")
        if not page.description:
            problem(kind, url, "meta description が無い")
        if not same_url(page.canonical, url):
            problem(kind, url, f"canonical が自身を指していない（{page.canonical}）")
        if page.h1 != 1:
            problem(kind, url, f"h1 が {page.h1} 個")
        for block in page.json_ld:
            try:
                json.loads(block)
            except ValueError:
                problem(kind, url, "構造化データ（JSON-LD）が JSON として読めない")
        if kind == "ハブ・静的":
            if url not in sitemap_urls and url.rstrip("/") not in [item.rstrip("/") for item in sitemap_urls]:
                problem(kind, url, "sitemap.xml に載っていない")
            for href in page.links:
                facet = facet_of(urllib.parse.urljoin(url, href))
                if facet and facet[0] in facet_keys:
                    hub_facets.add(facet)
    for field, label in (("title", "title"), ("description", "meta description")):
        seen = collections.defaultdict(list)
        for item in checked:
            if item[field]:
                seen[item[field]].append(item["url"].replace(base, "") or "/")
        for value, urls in seen.items():
            if len(urls) > 1:
                problem("重複", base + urls[0], f"{label} がほかのページと同じ（{'、'.join(urls[1:])}）")

    # 4. ファセット面: ハブのリンクとサイトマップの突き合わせ
    orphan = sitemap_facets - hub_facets
    for key, value in sorted(orphan)[:10]:
        problem("ファセット面", f"{base}/words?{key}={value}", "サイトマップに載っているのに、ハブからリンクされていない")
    if len(orphan) > 10:
        problem("ファセット面", base + "/sitemap-facets.xml", f"同じ問題がほかに {len(orphan) - 10} 面")

    # 5. インデックスさせない URL・存在しない URL・リダイレクト
    for label, path in MUST_NOINDEX:
        status, headers, text, _final = fetch(base + path)
        if status != 200:
            problem("閉じた URL", base + path, f"{label}: ステータスが {status}")
        elif not noindex(Page(text), headers):
            problem("閉じた URL", base + path, f"{label}: noindex が付いていない")
    for label, path in MUST_404:
        status, _headers, _text, _final = fetch(base + path)
        if status != 404:
            problem("閉じた URL", base + path, f"{label}: ステータスが {status}（404 のはず）")
    for label, url, destination in MUST_REDIRECT:
        status, headers, _text, _final = fetch(url, follow=False)
        location = headers.get("Location") or ""
        if status != 301 or not location.startswith(destination):
            problem("リダイレクト", url, f"{label}: {status} {location or '（Location 無し）'}（301 で {destination} のはず）")

    # 6. 数（docs/seo-plan.md §4.3 の表の取り直し）
    by_key = {key: {"hub": 0, "sitemap": 0} for key in facet_keys}
    for key, _value in hub_facets:
        by_key[key]["hub"] += 1
    for key, _value in sitemap_facets:
        by_key[key]["sitemap"] += 1
    summary = {
        "sitemap_urls": len(sitemap_urls), "words": len(word_urls), "static": len(static_urls),
        "facets_hub": len(hub_facets), "facets_sitemap": len(sitemap_facets), "by_key": by_key,
        "problems": len(problems), "disallow": disallows,
    }

    output_dir = os.path.join(OUTPUT_ROOT, args.month)
    os.makedirs(output_dir, exist_ok=True)
    earlier = sorted(name for name in os.listdir(OUTPUT_ROOT)
                     if name < args.month and os.path.exists(os.path.join(OUTPUT_ROOT, name, "site-check.json")))
    previous = None
    if earlier:
        with open(os.path.join(OUTPUT_ROOT, earlier[-1], "site-check.json"), encoding="utf-8") as file:
            previous = json.load(file)

    def diff(now, before):
        if before is None:
            return "—"
        return f"{now - before:+,}" if now != before else "±0"

    before_of = lambda name: previous.get(name) if previous else None
    lines = [f"# 本番の点検（{args.month}）", "",
             f"script/seo_site_check.py が {time.strftime('%Y-%m-%d %H:%M')} に本番を読んだ結果。見ているものは docs/seo-operations.md §5。", "",
             "## 1. 問題（1 行 1 問題）", ""]
    if problems:
        lines += ["| 型 | URL | 問題 |", "|---|---|---|"]
        lines += [f"| {kind} | `{urllib.parse.unquote(url)}` | {text} |" for kind, url, text in problems]
    else:
        lines += ["無し"]
    lines += ["", "## 2. 数", "",
              f"前の月: {earlier[-1] if earlier else '（記録なし）'}", "",
              "| | 数 | 前の月との差 |", "|---|---|---|",
              f"| sitemap.xml の URL | {len(sitemap_urls):,} | {diff(len(sitemap_urls), before_of('sitemap_urls'))} |",
              f"| うち単語詳細（公開語の数） | {len(word_urls):,} | {diff(len(word_urls), before_of('words'))} |",
              f"| うちそれ以外 | {len(static_urls):,} | {diff(len(static_urls), before_of('static'))} |",
              f"| ハブからリンクされたファセット面 | {len(hub_facets):,} | {diff(len(hub_facets), before_of('facets_hub'))} |",
              f"| sitemap-facets.xml に載る面 | {len(sitemap_facets):,} | {diff(len(sitemap_facets), before_of('facets_sitemap'))} |", "",
              "| 条件 | ハブからリンクされた面 | サイトマップに載る面 | 載らない面（公開語義が下限に届かない） |", "|---|---|---|---|"]
    lines += [f"| `{key}` | {counts['hub']} | {counts['sitemap']} | {counts['hub'] - counts['sitemap']} |" for key, counts in by_key.items()]
    lines += [f"| 計 | {len(hub_facets)} | {len(sitemap_facets)} | {len(hub_facets) - len(sitemap_facets)} |", "",
              "サイトマップに載せる下限は `IndexableFacets::SITEMAP_MIN_COUNT`。", "",
              f"robots.txt の Disallow: {'、'.join(f'`{path}`' for path in disallows) or '無し'}", "",
              "## 3. 見たページ", "", "| 型 | URL | title | meta description の字数 |", "|---|---|---|---|"]
    lines += [f"| {item['kind']} | `{urllib.parse.unquote(item['url'].replace(base, '') or '/')}` | {item['title'].replace('|', '｜')} | "
              f"{len(item['description'] or '')} |" for item in checked]
    lines += ["", "## 4. docs/seo-log.md の表 3 に足す行", "", "```",
              f"| {args.month} | {len(word_urls):,} | {len(hub_facets):,} | {len(sitemap_facets):,} | {len(problems)} |", "```", ""]
    report = "\n".join(lines)
    with open(os.path.join(output_dir, "site-check.md"), "w", encoding="utf-8") as file:
        file.write(report)
    with open(os.path.join(output_dir, "site-check.json"), "w", encoding="utf-8") as file:
        json.dump(summary, file, ensure_ascii=False, indent=2)
    print(report)
    print(f"書き出した: {os.path.join(output_dir, 'site-check.md')}", file=sys.stderr)


if __name__ == "__main__":
    main()
