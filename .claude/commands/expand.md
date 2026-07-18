---
description: 種語の上位概念を突き止め、同系統の単語をまとめて収集（word-expansion-research スキル）
argument-hint: "[任意: 収集軸の指定（例 キャラクター名）／入力ファイルパス。既定は軸をスキルが調査・選定、research/inputs/expansion.txt]"
---

`word-expansion-research` スキルを**明示的に**使って調査を実行してください。
似た名前の `word-notation-research`（表記）・`word-reading-research`（読み）・
`word-annotation-research`（アノテーション）とは**取り違えないこと**。

- 引数: $ARGUMENTS
- 引数の解釈: 引数が**ファイルパスに見えるなら入力パス**として使う。**それ以外の語句は収集軸**
  （例 `キャラクター名` `楽曲名` `必殺技名`）として使い、軸の選定をせずその軸で収集する。
  空なら既定（入力 `research/inputs/expansion.txt`／収集軸はスキルが調査して有望な軸を選定）。
- 出力ファイル: `research/outputs/expansion.txt`（上書き）。
- `.claude/skills/word-expansion-research/SKILL.md` の手順に厳密に従うこと
  （上位概念の特定と収集軸の選定 → 実在する一覧を出典に列挙 → 4原則・明らかに短い語でふるい分け →
  1種語×1軸あたり30語の上限 → 出典URL と confidence 付きの注記）。
  **有望な軸が無い種語は無理に拡張せず**、収集0件で理由を注記に書く。
- **でっち上げ厳禁**。記憶で語を並べず、必ず WebSearch で一覧を確認し、確認できた分だけを出すこと。

まず Skill ツールで `word-expansion-research` を起動し、入力ファイルを読んで調査し、出力ファイルを書き出してください。
