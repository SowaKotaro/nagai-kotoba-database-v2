---
description: 対象語の意味・ジャンル・エンティティ等を調査し提案JSONを作る（word-annotation-research スキル）
argument-hint: "[任意: 入力ファイルパス。既定 inputs_annotation_tmp.json]"
---

`word-annotation-research` スキルを**明示的に**使って調査を実行してください。
似た名前の `word-notation-research`（表記のみ）・`word-reading-research`（読み）とは**取り違えないこと**。

- 引数: $ARGUMENTS
- 入力ファイル: 上の引数が空でなければそれを入力パスに使う。空なら既定の `inputs_annotation_tmp.json`
  （管理画面「調査用データの書き出し」の JSON を保存したもの）。
- 出力ファイル: `outputs_annotation_tmp.json`（上書き。管理画面「提案 JSON の取り込み」にそのまま貼れる）。
- `.claude/skills/word-annotation-research/SKILL.md` の手順に厳密に従うこと
  （判断基準は docs/annotation-guidelines.md が正／各語「2周」で調査・裏取り／マスタは渡された一覧から一字一句同じ表記で選ぶ／
  同名の別語義は senses で複数返す／entry_score と confidence を付ける）。

まず Skill ツールで `word-annotation-research` を起動し、入力ファイルを読んで調査し、出力ファイルを書き出してください。
