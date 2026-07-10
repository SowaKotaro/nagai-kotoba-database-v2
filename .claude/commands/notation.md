---
description: 登録候補の「最も一般的な表記」を調査（word-notation-research スキル）
argument-hint: "[任意: 入力ファイルパス。既定 research/inputs/notation.txt]"
---

`word-notation-research` スキルを**明示的に**使って調査を実行してください。
似た名前の `word-reading-research`（読み）・`word-annotation-research`（アノテーション）とは**取り違えないこと**。

- 引数: $ARGUMENTS
- 入力ファイル: 上の引数が空でなければそれを入力パスに使う。空なら既定の `research/inputs/notation.txt`。
- 出力ファイル: `research/outputs/notation.txt`（上書き）。
- `.claude/skills/word-notation-research/SKILL.md` の手順に厳密に従うこと
  （annotation-guidelines §3 準拠の表記選定、固有名詞・ことわざ等の WebSearch 裏取り、confidence 付き注記）。

まず Skill ツールで `word-notation-research` を起動し、入力ファイルを読んで調査し、出力ファイルを書き出してください。
