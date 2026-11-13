---
description: 調査の自動実行(cron の research:auto)を今すぐ 1 回回す（research-auto-run スキル）
argument-hint: "[任意: cron（期限を守って cron と同じに起動）。既定は期限前でも新しい run を始める]"
allowed-tools: Skill, Bash(bin/rails research:auto:*), Bash(tail -n 40 research/auto/auto.log), Read, Glob
---

`research-auto-run` スキルを**明示的に**使ってください。段の調査(`/expand`・`/notation`・`/reading`)を自分で実行しないこと
(司令塔 `bin/rails research:auto` が `claude -p` で回す)。

- 引数: $ARGUMENTS

まず Skill ツールで `research-auto-run` を起動し、その手順どおりに `bin/rails research:auto` をバックグラウンドで起動して、結果を報告してください。
