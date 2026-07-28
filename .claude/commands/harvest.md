---
description: ニュースサイト等を巡回して収録候補の単語を収穫（word-harvest-research スキル）
argument-hint: "[任意: 朝 / 夕（セット指定）、または系統名。既定は全ソース]"
---

`word-harvest-research` スキルを**明示的に**使って調査を実行してください。
似た名前の `word-expansion-research`（種語からの補完）とは**取り違えないこと**
（harvest は種語を受け取らず、外部サイトを巡回する）。

- 引数: $ARGUMENTS
- 引数の解釈:
  - `朝` … 朝セット（エンタメ / ニュース / IT）の全ソースを巡回。出力は `<日付>-morning.txt`。
  - `夕` … 夕セット（スポーツ / 科学 / 学術 / 美術 / 書籍 / ファッション）の全ソースを巡回。出力は `<日付>-evening.txt`。
  - 系統名（`エンタメ` `ニュース` `IT` `スポーツ` `科学` `学術` `美術` `書籍` `ファッション`）… その系統だけ。出力は `<日付>-manual.txt`。
  - 空 … 両セットの全ソースを巡回。出力は `<日付>-manual.txt`。
- 出力ファイル: `research/outputs/harvest/<実行日 YYYY-MM-DD>-<セット>.txt`
  （日付＋セットごとに残す。同じ日の同じセットを再実行したときだけ上書き）。
- `.claude/skills/word-harvest-research/SKILL.md` の手順に厳密に従うこと
  （既提案リストの読み込み → ソース巡回 → 4原則・モーラ数のふるい → 既提案の除外 →
  出典URL付きの出力 → `research/harvest-seen.txt` への追記）。
- **でっち上げ厳禁**。実際に取得したページに書かれていた語だけを、記事の表記のまま出すこと。

まず Skill ツールで `word-harvest-research` を起動し、ソースを巡回して調査し、出力ファイルを書き出してください。
