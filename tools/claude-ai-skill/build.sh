#!/usr/bin/env bash
# claude.ai(スマホアプリ含む)の素のチャットにアップロードするスキルを、
# リポジトリ内の原本から生成する。原本を直したら、このスクリプトを再実行して差し替える。
#
#   使い方: bash tools/claude-ai-skill/build.sh
#   出力  : tmp/claude-ai-skill/ 以下と tmp/nagai-kotoba-reannotation.zip
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_NAME="nagai-kotoba-reannotation"
OUT="$ROOT/tmp/claude-ai-skill/$SKILL_NAME"
REF="$OUT/references"

rm -rf "$ROOT/tmp/claude-ai-skill" "$ROOT/tmp/$SKILL_NAME.zip"
mkdir -p "$REF"

# リポジトリ内のパス参照を、バンドル内の references/ に振り替える。
# 長いパスから先に置換する(短い方が先に当たると取りこぼす)。
rewrite_paths() {
  sed -e 's#\.\./word-annotation-research/SKILL\.md#references/annotation-procedure.md#g' \
      -e 's#\.claude/skills/word-annotation-research/SKILL\.md#references/annotation-procedure.md#g' \
      -e 's#\.\./\.\./\.\./docs/annotation-guidelines\.md#references/annotation-guidelines.md#g' \
      -e 's#docs/annotation-guidelines\.md#references/annotation-guidelines.md#g' \
      -e 's#\.\./\.\./\.\./config/linguistic_features_glossary\.yml#references/linguistic-features-glossary.yml#g' \
      -e 's#config/linguistic_features_glossary\.yml#references/linguistic-features-glossary.yml#g'
}

# 先頭の YAML フロントマター(--- で挟まれた塊)を落とす。
strip_frontmatter() {
  awk 'NR==1 && $0=="---" { infm=1; next } infm && $0=="---" { infm=0; next } !infm'
}

# --- SKILL.md: バンドル用のフロントマター + 運用の上書き + 原本の本文 ---
cat > "$OUT/SKILL.md" <<'HEADER'
---
name: nagai-kotoba-reannotation
description: 「長い言葉のデータベース」(nagai-kotoba-database-v2)の単語アノテーションを、チャットに貼られた JSON だけで調べ直すオフライン調査。アノテーション・コンソールの「再調査用JSON」や「調査用データの書き出し」JSON を貼って起動し、意味・ジャンル・エンティティ・品詞・語種・言語的特徴・別表記・立項スコアを調査して、取り込み画面に貼れる提案 JSON をチャットに返す。「再アノテーションして」「この語の注釈を調べ直して」「アノテーションを調べて」と言われたときに使う。
---

# 運用（このバンドル版の上書き・最優先）

このスキルは開発マシンのリポジトリから切り出した携帯用のバンドルで、**リポジトリもローカル
ファイルも存在しない環境（claude.ai のチャット・スマートフォンアプリ）で動かす**。以下は本文の
記述より優先する。

- **入力はチャットに貼られた JSON だけ。** `research/inputs/*.json` のようなファイルは存在しない。
  JSON が貼られていなければ、勝手に語を探しに行かずその場で聞く。
- **出力はチャットに貼る JSON 1つだけ。** `research/outputs/*.json` への書き出しは行わない
  （本文に「ファイルにも書き出す」とあっても実行しない）。オーナーが携帯からコピーして
  管理画面の「提案 JSON の取り込み」に貼るため、**JSON のコードブロックは必ず1つ**にする。
- **判断基準の原本は `references/` に同梱してある。** 本文がリポジトリ内のファイルを参照している
  箇所は、次に読み替える。
  - 調査手順・判定基準の正 → `references/annotation-procedure.md`
  - 収録基準・立項スコア・表記/読みの基準の正 → `references/annotation-guidelines.md`
  - 言語的特徴の定義と例の正 → `references/linguistic-features-glossary.yml`
  - 提案 JSON のスキーマと実例 → `references/schema.json` / `references/example.json`
- **まとめての調査（`words` 配列 + `masters` の書き出し形式）が貼られたときも受け付ける。**
  語ごとに同じ手順を回し、提案を `proposals` 配列に並べて返す。

---

HEADER
strip_frontmatter < "$ROOT/.claude/skills/word-reannotation-research/SKILL.md" | rewrite_paths >> "$OUT/SKILL.md"

# --- references/ ---
{
  echo "<!-- バンドル版: 判断基準の参照用。入出力に関する記述は SKILL.md 冒頭の「運用」が優先する。 -->"
  echo
  strip_frontmatter < "$ROOT/.claude/skills/word-annotation-research/SKILL.md" | rewrite_paths
} > "$REF/annotation-procedure.md"

rewrite_paths < "$ROOT/docs/annotation-guidelines.md" > "$REF/annotation-guidelines.md"
rewrite_paths < "$ROOT/config/linguistic_features_glossary.yml" > "$REF/linguistic-features-glossary.yml"
rewrite_paths < "$ROOT/.claude/skills/word-annotation-research/schema.json" > "$REF/schema.json"
cp "$ROOT/.claude/skills/word-annotation-research/example.json" "$REF/example.json"

# --- zip 化(claude.ai へのアップロード用) ---
cd "$ROOT/tmp/claude-ai-skill"
if command -v zip >/dev/null 2>&1; then
  zip -qr "$ROOT/tmp/$SKILL_NAME.zip" "$SKILL_NAME"
else
  python3 -c "
import shutil, sys
shutil.make_archive(sys.argv[1], 'zip', root_dir='.', base_dir=sys.argv[2])
" "$ROOT/tmp/$SKILL_NAME" "$SKILL_NAME"
fi

echo "生成しました:"
find "$OUT" -type f | sed "s#$ROOT/##" | sort
echo "zip: tmp/$SKILL_NAME.zip"
