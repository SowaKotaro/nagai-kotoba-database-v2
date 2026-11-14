#!/usr/bin/env python3
"""調査の自動実行(bin/rails research:auto)の run を、ブラウザで眺めるための静的な HTML を書き出す。

    python3 script/research_viewer.py

research/auto/ の下を読み、research/auto/index.html(run の一覧)と research/auto/runs/<run>/index.html
(段ごとの語の状態)を書き出す。どちらも gitignore の下で、本番には出ない。ファイルから開いたページは
ほかのファイルを読みに行けないので、表示と一括コピーに使うデータは HTML に埋め込む。
rake research:auto が最後に呼ぶので、cron でも /auto でも run が進めば作り直される。
ファイルの形と段の規則の正は ResearchRun・ResearchLedger と research/README.md の「自動実行」。
Python の標準ライブラリだけで動く。
"""

import html
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUTO = ROOT / "research/auto"
RUNS = AUTO / "runs"
SEEDS = ROOT / "research/inputs/seeds.txt"
PAGE = "index.html"
RUN_ID = re.compile(r"\A\d{8}-\d{6}\Z")
# 段の順と、段ごとの出力(ResearchRun の STAGE_DIRECTORIES・OUTPUT_FILES と同じ並び)。
STAGES = [
    ("expand", "01-expand/expansion.json", "拡張(/expand)"),
    ("notation", "02-notation/notation.json", "表記(/notation)"),
    ("reading", "03-reading/reading.json", "読み(/reading)"),
]
SEED_PREFIX = re.compile(r"\A\s*(?:\d+[.)．]|[-・])\s*")
SEED_SEPARATOR = re.compile(r"\A\s*-{3,}\s*\Z")


# ---- 読み取り ---------------------------------------------------------------

def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def run_ids():
    if not RUNS.is_dir():
        return []
    return sorted((p.name for p in RUNS.iterdir() if p.is_dir() and RUN_ID.match(p.name)), reverse=True)


def rejected_rows(directory):
    rows = []
    for line in (read_text(directory / "rejected.tsv") or "").splitlines():
        cells = line.split("\t")
        if len(cells) >= 4:
            rows.append({"stage": cells[0], "surface": cells[1], "reading": cells[2], "reason": cells[3]})
    return rows


def reason_kind(reason):
    """「重複: 〜」「読みが基準に届かない(〜)」から、内訳の見出しだけを取る。"""
    return re.split(r"[:(]", reason, maxsplit=1)[0].strip()


def remaining_seeds():
    """seeds.txt のうち、台帳で使っていない種語(ResearchPipeline#next_seeds と同じ読み方)。"""
    used = set()
    for line in (read_text(AUTO / "ledger.tsv") or "").splitlines():
        cells = line.split("\t")
        if len(cells) >= 6 and cells[2] == "seed":
            used.add(cells[5])
    seeds = []
    for line in (read_text(SEEDS) or "").splitlines():
        if SEED_SEPARATOR.match(line):
            continue
        seed = SEED_PREFIX.sub("", line).strip()
        if seed and seed not in used and seed not in seeds:
            seeds.append(seed)
    return seeds


def stage_items(directory, stage, output):
    """段の出力 JSON を、表の行(表示する列の辞書)の並びにする。出力が無ければ None。"""
    data = read_json(directory / output)
    if data is None:
        return None
    if stage == "expand":
        return [{"seed": seed.get("input", ""), "surface": c.get("surface", ""), "reading": c.get("reading", ""),
                 "match": {c.get("surface", "")}}
                for seed in data.get("seeds", []) for c in seed.get("candidates", [])]
    if stage == "notation":
        return [{"input": w.get("input", ""), "surface": w.get("surface", ""), "entry_score": w.get("entry_score"),
                 "confidence": w.get("confidence", ""), "note": w.get("note", ""),
                 "match": {w.get("surface", ""), w.get("input", "")}} for w in data.get("words", [])]
    return [{"input": w.get("input", ""), "surface": w.get("surface", ""), "reading": w.get("reading", ""),
             "alternatives": w.get("alternatives") or [], "confidence": w.get("confidence", ""),
             "note": w.get("notes", ""), "match": {w.get("surface", ""), w.get("input", "")}}
            for w in data.get("words", [])]


def attach_status(items, rejected):
    """却下の行(段・表層形)を突き合わせ、各行に却下の理由を付ける(無ければ通過)。"""
    reasons = {}
    for row in rejected:
        reasons.setdefault(row["surface"], row["reason"])
    for item in items:
        item["reason"] = next((reasons[name] for name in item["match"] if name in reasons), None)
    return items


def deliverables(directory):
    """一括登録に貼る 2 つ(step1 の register.txt の語、step2 の reading.json の words)。run が終わっていなければ None。"""
    register = read_text(directory / "register.txt")
    reading = read_json(directory / "reading.json")
    if register is None or reading is None:
        return None
    return {"register": [line for line in register.splitlines() if line.strip()], "words": reading.get("words", [])}


# ---- 描画 -------------------------------------------------------------------

def e(value):
    return html.escape("" if value is None else str(value))


def embed(value):
    """<script type="application/json"> に埋める JSON(</script> で閉じられないように < を逃がす)。"""
    return json.dumps(value, ensure_ascii=False).replace("<", "\\u003c")


CSS = """
/* 白地に薄い罫だけ。色は文字の濃淡と、却下の赤・通過の緑だけに使う */
:root { --ink: #1d1d1f; --sub: #6e6e73; --faint: #f6f6f7; --line: #e6e6e8; --edge: #d2d2d7;
  --pass: #1f7a45; --reject: #b42318; --reject-bg: #fef3f2; }
* { box-sizing: border-box; } [hidden] { display: none !important; }
body { margin: 0; background: #fff; color: var(--ink); -webkit-font-smoothing: antialiased;
  font: 15px/1.6 "Segoe UI", "Yu Gothic UI", "Hiragino Sans", "Noto Sans JP", "IPAexGothic", sans-serif; }
main { max-width: 1440px; margin: 0 auto; padding: 28px 40px 64px; }
h1 { font-size: 22px; margin: 8px 0 4px; letter-spacing: .02em; } h2 { font-size: 17px; margin: 32px 0 8px; }
p { margin: 4px 0; }
a { color: inherit; white-space: nowrap; text-decoration-color: var(--edge); text-underline-offset: 3px; }
a:hover { text-decoration-color: currentColor; }
.sub { color: var(--sub); }
/* チェックボックスとラジオ: 既定の部品を消して描き直す(墨の塗りに白の印) */
input[type=checkbox], input[type=radio] { appearance: none; -webkit-appearance: none; flex: none; width: 18px; height: 18px;
  margin: 0 6px 0 0; vertical-align: -4px; border: 1.5px solid var(--edge); border-radius: 5px; background: #fff center / 14px no-repeat;
  cursor: pointer; transition: background-color .12s, border-color .12s; }
input[type=radio] { border-radius: 50%; }
input[type=checkbox]:hover, input[type=radio]:hover { border-color: var(--sub); }
input[type=checkbox]:checked { background-color: var(--ink); border-color: var(--ink);
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M3.5 8.5l3 3 6-7' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E"); }
input[type=radio]:checked { background: var(--ink); border-color: var(--ink); box-shadow: inset 0 0 0 3.5px #fff; }
input:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
label { cursor: pointer; }
.card { border: 1px solid var(--line); border-radius: 10px; padding: 14px 18px; margin: 20px 0; }
.card > b:first-child { font-size: 14px; }
table { width: 100%; border-collapse: separate; border-spacing: 0; border: 1px solid var(--line); border-radius: 10px; overflow: clip; }
th, td { text-align: left; vertical-align: top; padding: 10px 14px; border-bottom: 1px solid var(--line); }
tbody tr:last-child td { border-bottom: 0; }
tbody tr:hover td { background: #fafafb; }
/* 一覧の行は、行のどこを押しても run のページへ行く(チェックボックスは除く)。チェックした行は淡く塗る */
tr[data-href] { cursor: pointer; } tr[data-href] a { text-decoration: none; }
tr:has(input[data-pick]:checked) td { background: #f1f3f6; }
th { font-size: 13px; font-weight: 400; color: var(--sub); white-space: nowrap; background: var(--faint); position: sticky; top: 0; z-index: 1; }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
td > label { white-space: nowrap; } tr.is-reviewed td, tr.is-reviewed a { color: var(--sub); }
.pass { color: var(--pass); font-weight: 800; } .reject { color: var(--reject); }
.note { color: var(--sub); font-size: 13px; max-width: 560px; }
.tag { display: inline-block; background: var(--faint); border-radius: 4px; padding: 0 6px; font-size: 13px; margin-right: 4px; }
.actions { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin: 10px 0 0; }
button { font: inherit; font-size: 14px; color: var(--ink); background: #fff; border: 1px solid var(--edge); border-radius: 8px; padding: 5px 14px; cursor: pointer; }
button:hover { background: var(--faint); border-color: var(--sub); }
.flash { font-size: 14px; font-weight: 800; }
.filter { display: flex; flex-wrap: wrap; gap: 8px; margin: 10px 0 8px; align-items: center; }
/* 絞り込みの選択肢は、押して切り替える札。入力の部品は見せず、選んだ札を墨で塗る */
.filter label { display: inline-flex; align-items: center; padding: 4px 12px; border-radius: 6px; background: var(--faint);
  font-size: 14px; user-select: none; transition: background-color .12s, color .12s; }
.filter label:hover { background: #ececee; }
.filter label:has(input:checked) { background: var(--ink); color: #fff; }
.filter label:has(input:checked) .count { color: #c7c7cc; }
.filter label:has(input:focus-visible) { outline: 2px solid var(--ink); outline-offset: 2px; }
.filter label input { position: absolute; opacity: 0; width: 1px; height: 1px; margin: 0; pointer-events: none; }
.filter label .count { margin-left: 6px; }
/* 絞り込みではないスイッチ(確認済みを隠す)は札にせず、チェックボックスのまま */
.filter label.sub, .filter label.sub:has(input:checked) { background: none; color: var(--sub); padding-left: 4px; }
.filter label.sub input { position: static; opacity: 1; width: 18px; height: 18px; margin: 0 6px 0 0; pointer-events: auto; }
.toolbar { display: flex; flex-wrap: wrap; gap: 4px 18px; align-items: baseline; margin: 20px 0 8px; }
.count { color: var(--sub); font-variant-numeric: tabular-nums; }
/* 拾い直しの手順(選んだ段の分だけ出す) */
.hint { margin: 12px 0 4px; padding: 10px 14px; background: var(--faint); border-radius: 8px; font-size: 14px; }
code { font: 13px ui-monospace, Consolas, monospace; background: #fff; border: 1px solid var(--line); border-radius: 4px; padding: 0 4px; }
.preview { margin-top: 12px; } .preview > summary { display: inline-flex; color: var(--sub); font-size: 14px; }
.preview > summary::before { content: "▸"; margin-right: 6px; } .preview[open] > summary::before { content: "▾"; }
.preview pre { margin: 6px 0 0; max-height: 360px; overflow: auto; background: var(--faint); border-radius: 8px;
  padding: 10px 14px; font: 13px/1.6 ui-monospace, Consolas, "IPAexGothic", monospace; white-space: pre-wrap; overflow-wrap: anywhere; }
/* ボード: 種語(左) → 拡張 → 表記 → 読み → 登録。種語ごとの塊の中で、拡張の候補 1 語が 1 行。
   欄は語と札だけを見せ、押すと理由とメモが開く(details) */
.board { --seed: 220px; --lanes: repeat(3, minmax(0, 1fr)) 56px; border: 1px solid var(--line); border-radius: 10px; overflow: clip; background: var(--line); display: grid; gap: 1px; }
.board-head, .group { display: grid; grid-template-columns: var(--seed) minmax(0, 1fr); gap: 1px; }
.board-head { position: sticky; top: 0; z-index: 1; }
.board-head .cell { background: var(--faint); display: flex; gap: 8px; align-items: baseline; font-size: 14px; }
.lanes-head, .lane { display: grid; grid-template-columns: var(--lanes); gap: 1px; }
.lanes { display: grid; gap: 1px; }
.group + .group { border-top: 1px solid var(--edge); }
.cell { background: #fff; padding: 6px 12px; min-width: 0; overflow-wrap: anywhere; }
.cell.seed { background: #fcfcfd; }
.cell.seed > summary { position: sticky; top: calc(var(--head, 0px) + 6px); } /* 長い塊でも、種語が見出しの下に残る */
summary { cursor: pointer; list-style: none; display: flex; flex-wrap: wrap; align-items: baseline; gap: 2px 8px; }
summary::-webkit-details-marker { display: none; }
.cell .word { font-weight: 800; }
.cell.is-rejected { background: #fffafa; box-shadow: inset 2px 0 0 var(--reject); }
.cell.is-rejected .word { color: var(--sub); font-weight: 400; }
.badge { color: var(--reject); background: var(--reject-bg); font-size: 12px; border-radius: 4px; padding: 0 6px; }
.mark { color: var(--sub); background: var(--faint); font-size: 12px; border-radius: 4px; padding: 0 6px; }
.cell.is-empty { background: #fcfcfd; }
.more { margin-top: 4px; display: grid; gap: 2px; }
.reason { color: var(--reject); font-size: 13px; }
.meta { font-size: 13px; color: var(--sub); }
.cell .note { max-width: none; line-height: 1.5; }
.result { text-align: center; }
#rejected td:first-child, #rejected th:first-child { width: 40px; }
"""

# 一括コピー。page-data の runs(run ごとの register と words)のうち、チェックした run(一覧)か、
# そのページの run(run のページ)の分をつなげてクリップボードに入れる。
SCRIPT = """
const data = JSON.parse(document.getElementById("page-data").textContent);
// 確認済みの run(人が見終えた run)。DB もファイルも書けないので、ブラウザの localStorage に run の名前を持つ
const REVIEWED_KEY = "research-viewer:reviewed";
function loadReviewed() {
  try { return new Set(JSON.parse(localStorage.getItem(REVIEWED_KEY) || "[]")); } catch (_) { return new Set(); }
}
function saveReviewed(set) {
  try { localStorage.setItem(REVIEWED_KEY, JSON.stringify([...set])); } catch (_) { /* 保存できなくても表示は続ける */ }
}
function chosenRuns() {
  const boxes = [...document.querySelectorAll("input[name=run]")];
  return boxes.length ? boxes.filter((box) => box.checked).map((box) => box.value) : Object.keys(data.runs);
}
function payload(kind, runs) {
  if (kind === "register") return runs.flatMap((id) => data.runs[id].register).join("\\n") + "\\n";
  return JSON.stringify({ version: "1", words: runs.flatMap((id) => data.runs[id].words) }, null, 2) + "\\n";
}
// コピーする中身のプレビュー(チェックした run が変わるたびに書き直す)
function updatePreview() {
  const pre = document.querySelector("[data-preview]");
  if (!pre) return;
  const kind = document.querySelector("input[name=preview]:checked").value;
  const runs = chosenRuns();
  const count = runs.reduce((sum, id) => sum + data.runs[id].register.length, 0);
  document.querySelector("[data-preview-count]").textContent = runs.length ? `${runs.length} run・${count} 語` : "run を選んでください";
  pre.textContent = runs.length ? payload(kind, runs) : "";
}
document.addEventListener("change", (event) => {
  if (event.target.matches("input[name=run], input[name=preview]")) updatePreview();
});
updatePreview();
// 一覧の行(data-href)は、行のどこを押しても run のページへ行く。リンクとチェックボックス(とそのラベル)は除く
document.addEventListener("click", (event) => {
  const row = event.target.closest("tr[data-href]");
  if (!row || event.target.closest("a, input, label")) return;
  location.href = row.dataset.href;
});
async function writeClipboard(text) {
  try { await navigator.clipboard.writeText(text); return; } catch (_) { /* file:// で拒まれたら下へ */ }
  const area = document.createElement("textarea");
  area.value = text; document.body.append(area); area.select();
  const copied = document.execCommand("copy"); area.remove();
  if (!copied) throw new Error("クリップボードに書けませんでした");
}
document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy]");
  if (!button) return;
  const flash = button.parentElement.querySelector(".flash");
  const runs = chosenRuns();
  if (!runs.length) { flash.textContent = "run を選んでください"; flash.className = "flash reject"; return; }
  try {
    await writeClipboard(payload(button.dataset.copy, runs));
    const count = runs.reduce((sum, id) => sum + data.runs[id].register.length, 0);
    flash.textContent = `${count} 語ぶんをコピーしました`; flash.className = "flash pass";
  } catch (error) {
    flash.textContent = error.message; flash.className = "flash reject";
  }
});
const boardHead = document.querySelector(".board-head");
if (boardHead) document.documentElement.style.setProperty("--head", `${boardHead.offsetHeight}px`);
document.addEventListener("change", (event) => {
  if (event.target.matches("[data-open-all]")) {
    document.querySelectorAll(".board details").forEach((details) => { details.open = event.target.checked; });
    return;
  }
  if (!event.target.matches("[data-filter]")) return;
  const show = event.target.checked;
  document.querySelectorAll(".lane.is-stopped").forEach((lane) => { lane.hidden = !show; });
  document.querySelectorAll(".group").forEach((group) => {
    group.hidden = !group.querySelector(".lane:not([hidden])");
  });
});
"""

COPY_BUTTONS = ("<div class=\"actions\"><button data-copy=\"register\">step1 用 register.txt をコピー</button>"
                "<button data-copy=\"reading\">step2 用 reading.json をコピー</button><span class=\"flash\"></span></div>"
                "<details class=\"preview\"><summary>コピーする中身を見る</summary>"
                "<div class=\"filter\"><label><input type=\"radio\" name=\"preview\" value=\"register\" checked> register.txt</label>"
                "<label><input type=\"radio\" name=\"preview\" value=\"reading\"> reading.json</label>"
                "<span class=\"sub\" data-preview-count></span></div><pre data-preview></pre></details>")


# タブの印: キリン(首の長い動物。長い言葉を集める道具なので)。絵文字を SVG の文字として描く
FAVICON = ("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E"
           "%3Ctext x='50' y='.9em' font-size='90' text-anchor='middle'%3E%F0%9F%A6%92%3C/text%3E%3C/svg%3E")


def page(title, body, data, extra_script=""):
    return (f"<!DOCTYPE html><html lang=\"ja\"><head><meta charset=\"utf-8\"><title>{e(title)}</title>"
            f"<link rel=\"icon\" href=\"{FAVICON}\">"
            f"<style>{CSS}</style></head><body><main>{body}</main>"
            f"<script type=\"application/json\" id=\"page-data\">{embed(data)}</script>"
            f"<script>{SCRIPT}{extra_script}</script></body></html>\n")


def counts_cell(report, stage):
    entry = next((r for r in report if r.get("stage") == stage), None)
    if not entry:
        return "<td class=\"num sub\">—</td>"
    return f"<td class=\"num\">{entry['input']} → <b>{entry['passed']}</b></td>"


def render_index(runs):
    rows = []
    for run_id, state, delivered in runs:
        report = state.get("report", [])
        seeds = "、".join(s.get("surface", "") for s in state.get("seeds", []))
        checkbox = f"<input type=\"checkbox\" name=\"run\" value=\"{e(run_id)}\" data-pick>" if delivered else ""
        final = f"<b>{len(delivered['register'])}</b>" if delivered else "<span class=\"sub\">途中</span>"
        rows.append(
            f"<tr data-run=\"{e(run_id)}\" data-href=\"runs/{e(run_id)}/{PAGE}\"><td>{checkbox}</td><td><a href=\"runs/{e(run_id)}/{PAGE}\">{e(run_id)}</a></td><td>{e(seeds)}</td>"
            f"{counts_cell(report, 'expand')}{counts_cell(report, 'notation')}{counts_cell(report, 'reading')}"
            f"<td class=\"num\">{final}</td>"
            f"<td><label class=\"sub\"><input type=\"checkbox\" name=\"reviewed\" value=\"{e(run_id)}\"> 確認済み</label></td></tr>")
    remaining = remaining_seeds()
    upcoming = f"(次: {e('、'.join(remaining[:5]))})" if remaining else ""
    body = (
        "<h1>調査の自動実行</h1>"
        f"<p><a href=\"{REJECTED_PAGE}\">落ちた語を段ごとに集めて見る →</a></p>"
        f"<p class=\"sub\">research/auto/ の run の一覧(新しい順)。各段の数は「入力 → 通過」。"
        f"seeds.txt の未使用の種語: <b>{len(remaining)}</b> 語{upcoming}</p>"
        f"<div class=\"card\"><b>チェックした run をまとめてコピー</b>{COPY_BUTTONS}</div>"
        "<div class=\"toolbar\"><label><input type=\"checkbox\" data-hide-reviewed checked> 確認済みの run を隠す</label>"
        "<span class=\"sub\">確認済み <b data-reviewed-count>0</b> 件(このブラウザに覚える)</span></div>"
        "<table><thead><tr><th></th><th>run</th><th>種語</th><th class=\"num\">拡張</th><th class=\"num\">表記</th>"
        "<th class=\"num\">読み</th><th class=\"num\">登録へ</th><th></th></tr></thead>"
        f"<tbody>{''.join(rows) or '<tr><td colspan=8 class=sub>run はまだありません</td></tr>'}</tbody></table>")
    data = {"runs": {run_id: delivered for run_id, _, delivered in runs if delivered}}
    return page("調査の自動実行", body, data, INDEX_SCRIPT)


# 一覧で、確認済みの run に印を付け、隠す(隠した run はコピーの対象からも外す)。
INDEX_SCRIPT = """
const reviewed = loadReviewed();
function applyReviewed() {
  const hide = document.querySelector("[data-hide-reviewed]").checked;
  let count = 0;
  document.querySelectorAll("tr[data-run]").forEach((row) => {
    const done = reviewed.has(row.dataset.run);
    if (done) count += 1;
    row.querySelector("input[name=reviewed]").checked = done;
    row.classList.toggle("is-reviewed", done);
    row.hidden = hide && done;
    const pick = row.querySelector("input[name=run]");
    if (pick && row.hidden) pick.checked = false;
  });
  document.querySelector("[data-reviewed-count]").textContent = count;
  updatePreview();
}
document.addEventListener("change", (event) => {
  if (event.target.matches("input[name=reviewed]")) {
    if (event.target.checked) reviewed.add(event.target.value); else reviewed.delete(event.target.value);
    saveReviewed(reviewed);
    applyReviewed();
  }
  if (event.target.matches("[data-hide-reviewed]")) applyReviewed();
});
applyReviewed();
"""


def build_board(directory):
    """種語ごとに、拡張の候補 1 語を 1 行として、表記・読みの段の結果を横につなげる。
    段の間は文字列でつなぐ(表記の input = 拡張の候補の表層形、読みの input = 表記の表層形)。"""
    rejected = rejected_rows(directory)
    items = {}
    for stage, output, _ in STAGES:
        found = stage_items(directory, stage, output)
        items[stage] = attach_status(found, [r for r in rejected if r["stage"] == stage]) if found is not None else None
    expansion = read_json(directory / STAGES[0][1]) or {}
    notation_by_input = {item["input"]: item for item in items["notation"] or []}
    reading_by_input = {item["input"]: item for item in items["reading"] or []}
    groups = []
    for seed in expansion.get("seeds", []):
        lanes = []
        for candidate in (i for i in items["expand"] or [] if i["seed"] == seed.get("input", "")):
            notation = None if candidate["reason"] else notation_by_input.get(candidate["surface"])
            reading = None if notation is None or notation["reason"] else reading_by_input.get(notation["surface"])
            lanes.append({"expand": candidate, "notation": notation, "reading": reading})
        groups.append({"seed": seed.get("input", ""), "note": seed.get("note", ""), "lanes": lanes})
    return groups, items


# 却下の理由の短い札(欄には札だけを出し、全文は開いたときに出す)。キーは reason_kind の見出し。
SHORT_REASONS = {"重複": "重複", "読みが基準に届かない": "字数不足", "立項スコアが満点でない": "立項", "立項スコアが低い": "立項",
                 "確信度が high でない": "確信度", "確信度が low": "確信度", "読みが揺れる": "読み揺れ"}


def short_reason(item):
    kind = reason_kind(item["reason"])
    label = SHORT_REASONS.get(kind, kind)
    if label == "立項":
        return f"立項 {item.get('entry_score')}"
    if label == "確信度":
        return f"確信度 {item.get('confidence')}"
    return label


def stage_summary(found):
    if found is None:
        return "<span class=\"sub\">まだ</span>"
    passed = sum(1 for item in found if not item["reason"])
    return f"<span class=\"count\">{len(found)} → <span class=\"pass\">{passed}</span></span>"


def cell(item, word, details, mark=""):
    """1 段の欄。畳んだ状態は語と札だけ。押すと却下の理由・付帯の値・メモが開く。"""
    rejected = item["reason"]
    badge = f"<span class=\"badge\">{e(short_reason(item))}</span>" if rejected else mark
    reason = f"<div class=\"reason\">{e(rejected)}</div>" if rejected else ""
    note = f"<div class=\"note\">{e(item['note'])}</div>" if item.get("note") else ""
    return (f"<details class=\"cell{' is-rejected' if rejected else ''}\"><summary><span class=\"word\">{e(word)}</span>{badge}</summary>"
            f"<div class=\"more\">{reason}{details}{note}</div></details>")


def expand_cell(item):
    return cell(item, item["surface"], f"<div class=\"meta\">{e(item['reading'])}</div>")


def notation_cell(item):
    changed = item["input"] != item["surface"]
    details = (f"<div class=\"meta\">立項 {e(item['entry_score'])} · {e(item['confidence'])}</div>"
               + (f"<div class=\"meta\">← {e(item['input'])} から直した</div>" if changed else ""))
    return cell(item, item["surface"], details, "<span class=\"mark\">直</span>" if changed else "")


def reading_cell(item):
    alternatives = "、".join(a if isinstance(a, str) else str(a.get("reading", a)) for a in item["alternatives"])
    details = (f"<div class=\"meta\">{e(item['surface'])} · {e(item['confidence'])}</div>"
               + (f"<div class=\"meta\">別の読み: {e(alternatives)}</div>" if alternatives else ""))
    return cell(item, item["reading"], details)


def lane_html(lane, items):
    expand, notation, reading = lane["expand"], lane["notation"], lane["reading"]
    stopped = next((item for item in (expand, notation, reading) if item and item["reason"]), None)
    reached = not stopped and reading is not None
    cells = [expand_cell(expand)]
    # 却下された段より右は空ける。前の段を通ったのに次の段の出力に無ければ「まだ」(段に届いていない・失敗)
    for item, render, stage in ((notation, notation_cell, "notation"), (reading, reading_cell, "reading")):
        if item:
            cells.append(render(item))
        elif stopped or items[stage] is not None:
            cells.append("<div class=\"cell is-empty\"></div>")
        else:
            cells.append("<div class=\"cell is-empty\"><span class=\"sub\">まだ</span></div>")
    result = "<div class=\"cell result pass\">✓</div>" if reached else "<div class=\"cell result\"></div>"
    return f"<div class=\"lane{' is-stopped' if not reached else ''}\">{''.join(cells)}{result}</div>"


def render_board(groups, items):
    head = ("<div class=\"board-head\"><div class=\"cell\"><b>種語</b></div><div class=\"lanes-head\">"
            + "".join(f"<div class=\"cell\"><b>{e(label)}</b>{stage_summary(items[stage])}</div>" for stage, _, label in STAGES)
            + "<div class=\"cell result\"><b>登録</b></div></div></div>")
    rows = []
    for group in groups:
        lanes = "".join(lane_html(lane, items) for lane in group["lanes"]) or \
            "<div class=\"lane is-stopped\"><div class=\"cell is-empty\"><span class=\"sub\">拡張なし</span></div></div>"
        seed = (f"<details class=\"cell seed\"><summary><span class=\"word\">{e(group['seed'])}</span></summary>"
                f"<div class=\"more\"><div class=\"note\">{e(group['note'])}</div></div></details>")
        rows.append(f"<div class=\"group\">{seed}<div class=\"lanes\">{lanes}</div></div>")
    return ("<div class=\"filter\"><label><input type=\"checkbox\" data-filter checked> 途中で却下された語も表示</label>"
            "<label><input type=\"checkbox\" data-open-all> 理由とメモを全部開く</label></div>"
            f"<div class=\"board\">{head}{''.join(rows)}</div>")


def render_run(run_id, state, delivered):
    directory = RUNS / run_id
    groups, items = build_board(directory)
    seeds_count = len(state.get("seeds", []))
    parts = [
        f"<p><a href=\"../../{PAGE}\">← run の一覧</a></p>",
        f"<h1>run {e(run_id)}</h1>",
        f"<p class=\"sub\">作成 {e(state.get('created_on'))} / 種語 {seeds_count} 語 / 公開語の写し {e(state.get('corpus_fetched_at'))}</p>",
    ]
    if delivered:
        parts.append(f"<div class=\"card\"><b>一括登録に貼る</b>({len(delivered['register'])} 語){COPY_BUTTONS}</div>")
    parts.append(render_board(groups, items))
    data = {"runs": {run_id: delivered} if delivered else {}}
    return page(f"run {run_id}", "".join(parts), data)


REJECTED_PAGE = "rejected.html"

# 落ちた語を拾い直すときの手順(段ごと)。自動実行ではなく、個別のスキルを手で回す。
RESCUE_STEPS = {
    "expand": "表記からやり直す: 「語のリストをコピー」→ <code>research/inputs/notation.txt</code> に貼り、<code>/notation</code> を実行。"
              "通った語を <code>research/inputs/reading.txt</code> に貼って <code>/reading</code> → 一括登録へ。",
    "notation": "読みからやり直す: 「語のリストをコピー」→ <code>research/inputs/reading.txt</code> に貼り、<code>/reading</code> を実行。"
                "一括登録の step1 に語のリスト、step2 に <code>research/outputs/reading.json</code> を貼る。",
    "reading": "登録へ進める: 「語のリストをコピー」→ 一括登録の step1 に貼り、読みは MeCab の暫定読みを見て手で確かめる。"
               "調べ直すなら <code>research/inputs/reading.txt</code> に貼って <code>/reading</code> を実行。",
}

# 落ちた語の一覧で、段・run の絞り込みと、チェックした語のコピー(1 行 1 語)。
REJECTED_SCRIPT = """
const filters = () => ({
  stage: document.querySelector("input[name=stage]:checked").value,
  runs: new Set([...document.querySelectorAll("input[name=pick-run]:checked")].map((box) => box.value)),
});
function applyFilters() {
  const { stage, runs } = filters();
  let shown = 0;
  document.querySelectorAll("#rejected tbody tr").forEach((row) => {
    row.hidden = row.dataset.stage !== stage || !runs.has(row.dataset.run);
    if (row.hidden) row.querySelector("input").checked = false; else shown += 1;
  });
  document.getElementById("shown").textContent = shown;
  document.querySelectorAll("[data-hint]").forEach((hint) => { hint.hidden = hint.dataset.hint !== stage; });
  updateCount();
}
function checkedRows() {
  return [...document.querySelectorAll("#rejected tbody tr:not([hidden]) input:checked")].map((box) => box.closest("tr"));
}
function updateCount() { document.getElementById("picked").textContent = checkedRows().length; }
document.addEventListener("change", (event) => {
  if (event.target.matches("input[name=stage], input[name=pick-run]")) applyFilters();
  if (event.target.matches("[data-all]")) {
    document.querySelectorAll("#rejected tbody tr:not([hidden]) input").forEach((box) => { box.checked = event.target.checked; });
  }
  updateCount();
});
document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy-list]");
  if (!button) return;
  const flash = button.parentElement.querySelector(".flash");
  const rows = checkedRows();
  if (!rows.length) { flash.textContent = "語を選んでください"; flash.className = "flash reject"; return; }
  const text = rows.map((row) => row.dataset[button.dataset.copyList]).join("\\n") + "\\n";
  try { await writeClipboard(text); flash.textContent = `${rows.length} 語をコピーしました`; flash.className = "flash pass"; }
  catch (error) { flash.textContent = error.message; flash.className = "flash reject"; }
});
// 一覧で確認済みにした run は、選択を外して隠す(トグルで出せる。出したときは選び直す)
const reviewed = loadReviewed();
function applyReviewed() {
  const hide = document.querySelector("[data-hide-reviewed]").checked;
  document.querySelectorAll("[data-run-label]").forEach((label) => {
    if (!reviewed.has(label.dataset.runLabel)) return;
    label.hidden = hide;
    label.querySelector("input").checked = !hide;
  });
  applyFilters();
}
document.addEventListener("change", (event) => { if (event.target.matches("[data-hide-reviewed]")) applyReviewed(); });
applyReviewed();
"""


def render_rejected(runs):
    """全 run の、段ごとに落ちた語。段と run で絞り、チェックした語をリストでコピーする(拾い直しの下ごしらえ)。"""
    rows = []
    counts = Counter()
    for run_id, _, _ in runs:
        directory = RUNS / run_id
        groups, items = build_board(directory)
        seed_of = {lane["expand"]["surface"]: group["seed"] for group in groups for lane in group["lanes"]}
        # 表記の段は読みを出さないので、拡張の段で付いた読みを添える
        expand_reading = {item["surface"]: item["reading"] for item in items["expand"] or []}
        for stage, _, _ in STAGES:
            for item in items[stage] or []:
                if not item["reason"]:
                    continue
                counts[stage] += 1
                seed = seed_of.get(item["surface"]) or seed_of.get(item.get("input", ""), "")
                reading = item.get("reading") or expand_reading.get(item.get("input", ""), "")
                changed = (f"<div class=\"meta\">← {e(item['input'])} から直した</div>"
                           if stage == "notation" and item["input"] != item["surface"] else "")
                extra = (f"<div class=\"meta\">{e(reading)} · 立項 {e(item.get('entry_score'))} · {e(item.get('confidence'))}</div>"
                         if stage == "notation" else f"<div class=\"meta\">{e(reading)}</div>")
                note = f"<div class=\"note\">{e(item['note'])}</div>" if item.get("note") else ""
                rows.append(
                    f"<tr data-stage=\"{stage}\" data-run=\"{e(run_id)}\" data-surface=\"{e(item['surface'])}\""
                    f" data-line=\"{e(item['surface'])}\t{e(reading)}\t{e(item['reason'])}\">"
                    f"<td><input type=\"checkbox\" data-pick></td><td>{e(seed)}</td>"
                    f"<td><details><summary><span class=\"word\">{e(item['surface'])}</span>"
                    f"<span class=\"badge\">{e(short_reason(item))}</span></summary>"
                    f"<div class=\"more\"><div class=\"reason\">{e(item['reason'])}</div>{changed}{extra}{note}</div></details></td>"
                    f"<td class=\"sub\">{e(run_id)}</td></tr>")
    stages = "".join(
        f"<label><input type=\"radio\" name=\"stage\" value=\"{stage}\"{' checked' if stage == 'notation' else ''}>"
        f" {e(label)}で落ちた語 <span class=\"count\">{counts[stage]}</span></label>" for stage, _, label in STAGES)
    run_boxes = "".join(f"<label data-run-label=\"{e(run_id)}\"><input type=\"checkbox\" name=\"pick-run\" value=\"{e(run_id)}\" checked>"
                        f" {e(run_id)}</label>" for run_id, _, _ in runs)
    run_boxes += "<label class=\"sub\"><input type=\"checkbox\" data-hide-reviewed checked> 確認済みの run を隠す</label>"
    body = (
        f"<p><a href=\"{PAGE}\">← run の一覧</a></p><h1>落ちた語</h1>"
        "<p class=\"sub\">段と run で絞り、拾い直したい語にチェックを付けてコピーする。語を押すと却下の理由とメモが開く。</p>"
        f"<div class=\"card\"><div class=\"filter\">{stages}</div><div class=\"filter\">{run_boxes}</div>"
        + "".join(f"<p class=\"hint\" data-hint=\"{stage}\" hidden>{RESCUE_STEPS[stage]}</p>" for stage, _, _ in STAGES) +
        "<div class=\"actions\"><span>表示 <b id=\"shown\">0</b> 語 / 選択 <b id=\"picked\">0</b> 語</span>"
        "<button data-copy-list=\"surface\">語のリストをコピー</button>"
        "<button data-copy-list=\"line\">語・読み・理由(TSV)をコピー</button><span class=\"flash\"></span></div></div>"
        "<table id=\"rejected\"><thead><tr><th><input type=\"checkbox\" data-all></th><th>種語</th><th>落ちた語</th>"
        f"<th>run</th></tr></thead><tbody>{''.join(rows)}</tbody></table>")
    return page("落ちた語", body, {"runs": {}}, REJECTED_SCRIPT)


# ---- 書き出し ---------------------------------------------------------------

def write(path, content):
    """書きかけを開かれないよう、隣に書いてから置き換える。"""
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def main():
    if not AUTO.is_dir():
        print(f"{AUTO} がありません(run がまだ無い)")
        return
    runs = []
    for run_id in run_ids():
        directory = RUNS / run_id
        runs.append((run_id, read_json(directory / "state.json") or {}, deliverables(directory)))
    for run_id, state, delivered in runs:
        write(RUNS / run_id / PAGE, render_run(run_id, state, delivered))
    write(AUTO / PAGE, render_index(runs))
    write(AUTO / REJECTED_PAGE, render_rejected(runs))
    print(f"{AUTO / PAGE} を書き出しました(run {len(runs)} 件)")


if __name__ == "__main__":
    main()
