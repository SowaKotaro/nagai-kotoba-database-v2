---
description: 公開済みの語すべてを、指定した言語学的特徴の目で点検し直す（word-feature-audit スキル）
argument-hint: "[任意: 入力ファイルパス。既定 research/inputs/features.json]"
---

`word-feature-audit` スキルを**明示的に**使って点検を実行してください。
似た名前の `word-annotation-research`（新しい語の注釈）・`word-reannotation-research`（1語のやり直し）とは**取り違えないこと**。

- 引数: $ARGUMENTS
- 入力ファイル: 上の引数が空でなければそれを入力パスに使う。空なら既定の `research/inputs/features.json`
  （管理画面「言語学的特徴の点検」の書き出しを保存したもの）。
- 出力ファイル: `research/outputs/features.json`（上書き。管理画面「点検結果の取り込み」にそのまま貼れる）。
- `.claude/skills/word-feature-audit/SKILL.md` の手順に厳密に従うこと
  （判断基準は `.claude/skills/word-annotation-research/linguistic-features.md` が正／`features_to_check` の特徴だけを点検する／
  足す前にいま付いている特徴と見比べる／`target`・`target_reading` は表層形と語義の読みからそのまま切り出す）。

まず Skill ツールで `word-feature-audit` を起動し、入力ファイルを読んで点検し、出力ファイルを書き出してください。
