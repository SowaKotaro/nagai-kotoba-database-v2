---
description: ニュースサイト等を巡回して収録候補の単語を収穫（word-harvest-research スキル）
argument-hint: "[任意: 巡回する系統（エンタメ / ニュース / IT）。既定は全系統]"
---

`word-harvest-research` スキルを**明示的に**使って調査を実行してください。
似た名前の `word-expansion-research`（種語からの補完）とは**取り違えないこと**
（harvest は種語を受け取らず、外部サイトを巡回する）。

- 引数: $ARGUMENTS
- 引数の解釈: `エンタメ` / `ニュース` / `IT` のいずれかならその系統のソースだけを巡回する。
  空なら全系統を巡回する。
- 出力ファイル: `research/outputs/harvest/<実行日 YYYY-MM-DD>.txt`（日付ごとに残す。同日再実行のみ上書き）。
- `.claude/skills/word-harvest-research/SKILL.md` の手順に厳密に従うこと
  （既提案リストの読み込み → ソース巡回 → 4原則・モーラ数のふるい → 既提案の除外 →
  出典URL付きの出力 → `research/harvest-seen.txt` への追記）。
- **でっち上げ厳禁**。実際に取得したページに書かれていた語だけを、記事の表記のまま出すこと。

まず Skill ツールで `word-harvest-research` を起動し、ソースを巡回して調査し、出力ファイルを書き出してください。
