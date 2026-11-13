# -*- coding: utf-8 -*-
"""旧 .com の /words/:id を、.jp の /words/:id へ 301 するための nginx の対応表を作り直す道具。

旧 .com と .jp は id が別なので、表層形・別表記・読みで突き合わせる（docs/seo-plan.md §12.5・§12.6）。
.jp で語が公開されるたびに対応が増えるので、移行が進んだら同じコマンドで作り直し、
.com のサーバの対応表を差し替える。標準ライブラリだけで動き、アプリにも DB にも触れない。

    python3 script/com_redirect_map.py

入力:
  research/inputs/com-words.csv   旧 .com の全語（id,surface,reading）。旧 .com は語を足さないので作り直さない
  https://nagai-kotoba-database.jp/llms-full.txt   .jp の公開語（表層形・別表記・読み）。--jp-file で保存済みのファイルも渡せる
出力（どちらも gitignore 済み）:
  research/outputs/com-redirect/com-to-jp-words.map   nginx の map に include する対応表（「/words/旧id /words/新id;」）
  research/outputs/com-jp-mapping.csv    全語の突き合わせの結果（一致の種類つき。目で確かめる用）
"""
import argparse
import collections
import csv
import os
import re
import sys
import unicodedata
import urllib.request

JP_FULL_URL = "https://nagai-kotoba-database.jp/llms-full.txt"

# 一致の種類。上から順に試し、最初に当たったものを採る。
EXACT = "表層形が一致"
ALTERNATE = "別表記に一致"
LOOSE = "表記ゆれで一致"
READING = "読みだけ一致"
NONE = "不一致"
KINDS = [EXACT, ALTERNATE, LOOSE, READING, NONE]

# 表記ゆれとして無視する文字（空白・中黒・長音以外の記号）。全角半角と大文字小文字は NFKC と lower で畳む。
IGNORED = re.compile(r"[\s・=＝\-‐－―〜~!！?？、。,.「」『』()（）'’\"”“:：/／]")


def loose(text):
    return IGNORED.sub("", unicodedata.normalize("NFKC", text)).lower()


def read_jp_words(text):
    """llms-full.txt から、公開語ごとの id・表層形・別表記・読みを取り出す。"""
    words, current = [], None
    for line in text.splitlines():
        if line.startswith("### "):
            current = {"surface": line[4:], "id": None, "readings": set(), "alternates": set()}
            words.append(current)
        elif current is None:
            continue
        elif line.startswith("- URL: "):
            current["id"] = line.rsplit("/", 1)[1]
        elif line.startswith("- 読み: "):
            current["readings"].add(re.sub(r"\(\d+字.*$", "", line[6:]))
        elif line.startswith("- 別表記: "):
            for item in line[7:].split("、"):
                matched = re.match(r"(.*)\(([^()]*)\)$", item.strip())
                if matched:
                    current["alternates"].add(matched.group(1))
                    current["readings"].add(matched.group(2))
                else:
                    current["alternates"].add(item.strip())
    return [word for word in words if word["id"]]


def build_index(jp_words):
    by_surface = {word["surface"]: word["id"] for word in jp_words}
    by_alternate, by_loose = {}, {}
    by_reading = collections.defaultdict(set)
    for word in jp_words:
        for alternate in word["alternates"]:
            by_alternate.setdefault(alternate, word["id"])
            by_loose.setdefault(loose(alternate), word["id"])
    for word in jp_words:
        by_loose[loose(word["surface"])] = word["id"]  # 表層形を別表記より優先する
        for reading in word["readings"]:
            by_reading[reading].add(word["id"])
    return by_surface, by_alternate, by_loose, by_reading


def match(surface, reading, index):
    by_surface, by_alternate, by_loose, by_reading = index
    if surface in by_surface:
        return EXACT, by_surface[surface]
    if surface in by_alternate:
        return ALTERNATE, by_alternate[surface]
    if loose(surface) in by_loose:
        return LOOSE, by_loose[loose(surface)]
    # 読みだけの一致は、その読みを持つ公開語が 1 つのときだけ採る（同音の別の語へ飛ばさない）
    if reading and len(by_reading.get(reading, ())) == 1:
        return READING, next(iter(by_reading[reading]))
    return NONE, ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--com", default="research/inputs/com-words.csv")
    parser.add_argument("--jp-file", help="保存済みの llms-full.txt（省くと本番から 1 回だけ取得する）")
    parser.add_argument("--map-out", default="research/outputs/com-redirect/com-to-jp-words.map")
    parser.add_argument("--csv-out", default="research/outputs/com-jp-mapping.csv")
    args = parser.parse_args()

    if args.jp_file:
        with open(args.jp_file, encoding="utf-8") as file:
            jp_text = file.read()
    else:
        request = urllib.request.Request(JP_FULL_URL, headers={"User-Agent": "com-redirect-map"})
        with urllib.request.urlopen(request, timeout=60) as response:
            jp_text = response.read().decode("utf-8")
    jp_words = read_jp_words(jp_text)
    if not jp_words:
        sys.exit("llms-full.txt から公開語を読めなかった（書式が変わっていないか確かめる）")
    index = build_index(jp_words)
    jp_surface = {word["id"]: word["surface"] for word in jp_words}

    with open(args.com, encoding="utf-8", newline="") as file:
        com_words = [(int(row["id"]), row["surface"], row["reading"]) for row in csv.DictReader(file)]
    com_words.sort()

    rows, counts = [], collections.Counter()
    for com_id, surface, reading in com_words:
        kind, jp_id = match(surface, reading, index)
        counts[kind] += 1
        rows.append((com_id, surface, reading, kind, jp_id))

    os.makedirs(os.path.dirname(args.map_out), exist_ok=True)
    with open(args.csv_out, "w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["com_id", "com_surface", "com_reading", "match", "jp_id"])
        writer.writerows(rows)
    with open(args.map_out, "w", encoding="utf-8") as file:
        file.write("# script/com_redirect_map.py が作る。手で直さない（旧 .com の /words/:id → .jp の /words/:id）\n")
        for com_id, _surface, _reading, kind, jp_id in rows:
            if kind != NONE:
                file.write(f"/words/{com_id} /words/{jp_id};\n")

    matched = len(rows) - counts[NONE]
    print(f".jp の公開語 {len(jp_words)} / 旧 .com の語 {len(rows)}")
    print(f"行き先が決まった語 {matched}（" + "、".join(f"{kind} {counts[kind]}" for kind in KINDS[:-1]) + f"）/ {NONE} {counts[NONE]}")
    print(f"対応表: {args.map_out} / 突き合わせの結果: {args.csv_out}")
    reading_only = [(com_id, surface, jp_id) for com_id, surface, _reading, kind, jp_id in rows if kind == READING]
    if reading_only:
        print(f"{READING}（表記が違うので、同じ語かを目で確かめる）:")
        for com_id, surface, jp_id in reading_only:
            print(f"  {com_id} {surface} → {jp_id} {jp_surface[jp_id]}")


if __name__ == "__main__":
    main()
