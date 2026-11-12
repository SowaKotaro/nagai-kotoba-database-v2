---
description: 単語の「最も一般的な表記と読み(カタカナ)」を調査（word-reading-research スキル）
argument-hint: "[任意: 入力ファイルパス／--out 出力ディレクトリ。既定 research/inputs/reading.txt]"
---

`word-reading-research` スキルを**明示的に**使って調査を実行してください。
似た名前の `word-notation-research`（表記のみ）・`word-annotation-research`（アノテーション）とは**取り違えないこと**。

- 引数: $ARGUMENTS
- 引数の解釈: `--out <ディレクトリ>` があれば、出力をそのディレクトリに書く。残りの引数が空でなければそれを入力パスに使う。空なら既定の `research/inputs/reading.txt`。
- 出力ファイル: `reading.json`（上書き。step2 の取り込み欄にそのまま貼れる JSON）。置き場所は `--out` のディレクトリ、無ければ `research/outputs/`（SKILL.md に書かれた `research/outputs/` の出力パスは、`--out` があればそのディレクトリに読み替える）。
- `.claude/skills/word-reading-research/SKILL.md` の手順に厳密に従うこと
  （MeCab の読みは参照しない／固有名詞・ことわざ等は WebSearch で裏取り／読みはカタカナ・助詞は表記どおりのかな）。

まず Skill ツールで `word-reading-research` を起動し、入力ファイルを読んで調査し、出力ファイルを書き出してください。
