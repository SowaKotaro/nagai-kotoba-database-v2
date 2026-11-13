---
name: research-auto-run
description: nagai-kotoba-database-v2 の「調査の自動実行」(cron で隔日に動く bin/rails research:auto。seeds.txt の種語を /expand → /notation → /reading と通し、一括登録に貼る register.txt と reading.json を作る)を、cron を待たずに今すぐ 1 回動かす。中身は cron と同じコード(ResearchPipeline)で、前回の run から期限(`ResearchPipeline::INTERVAL_DAYS` 日)が来ていなくても新しい run を始める。「自動実行を今すぐ回して」「seeds の run を回して」「cron の run を手で動かして」「/auto」と言われたときに使う。各段の調査はこのスキルでは行わない(司令塔が claude -p で回す)。
allowed-tools: Bash(bin/rails research:auto:*), Bash(tail -n 40 research/auto/auto.log), Read, Glob
---

# 調査の自動実行を今すぐ回す

cron が動かしている `bin/rails research:auto`(Issue 112)を、このセッションから 1 回起動する。
**規則の正は `ResearchPipeline`(起動・期限・種語)と `ResearchRun`(段とふるい)、運用の正は `research/README.md` の「自動実行」**。
このスキルはそれを呼ぶだけで、段の調査・ふるい・重複の照合を自分でやらない(やると cron と結果がずれる)。

## 引数

- 空(既定) … `FORCE=1` を付けて起動する。前回の run から `ResearchPipeline::INTERVAL_DAYS` 日経っていなくても、新しい run を始める。
- `cron` … `FORCE` を付けずに起動する(cron と完全に同じ。期限前なら、途中の run の続きと inbox の注釈だけを進める)。

## 手順

1. 起動する前に、ユーザーへ次の 2 点を一言で伝える(確認は待たずに進めてよい)。
   - seeds.txt の未使用の種語を先頭から `ResearchPipeline::SEEDS_PER_RUN` 語使う(台帳に記録され、cron の次の run はその続きから取る)。
   - 新しい run を始めると、cron が次に新しい run を始めるのは、その日から `INTERVAL_DAYS` 日後になる(期限は最後の run の日付で数える)。
2. Bash で、**バックグラウンド実行**(`run_in_background: true`)で起動する。数分〜数十分かかる(段ごとの上限は `ClaudeResearchRunner::TIMEOUT`)。
   - 既定: `bin/rails research:auto FORCE=1 >> research/auto/auto.log 2>&1`
   - `cron`: `bin/rails research:auto >> research/auto/auto.log 2>&1`
   - ログは cron と同じ `research/auto/auto.log` に追記する(どちらの起動も 1 本のログで追える)。
   - 終わるのを待つ間に、ほかのコマンドを打って様子を見に行かない(終われば通知が来る)。
3. 終わったら `tail -n 40 research/auto/auto.log` で、今回の起動の行を読む。
4. 結果をユーザーに数行で返す。
   - 新しい run を通し切った(`done`): `research/auto/runs/<run>/summary.md` を Read し、種語・段ごとの件数・却下の内訳を要約する。
     続けて、人がやること(一括登録 step1 に `register.txt`、step2 に `reading.json` を貼る)と、その 2 つのパスを示す。
   - 段に失敗した: ログの行(何回目か・run を止めたか)と、その段の `claude.log` のパス(`research/auto/runs/<run>/<段>/claude.log`)を示す。
     利用上限で落ちたときは、次の起動(cron か、もう一度このスキル)で続きから進む。
   - 「前の起動がまだ動いている」: cron などの起動と重なった。何もしていない。
   - 「未使用の種語が残っていません」: `research/inputs/seeds.txt` に種語を足すよう伝える。
   - inbox の注釈を回した行があれば、`research/auto/annotation/<日時>/annotation.json` を「提案 JSON の取り込み」に貼るよう伝える。

## してはいけないこと

- 段の調査(/expand・/notation・/reading)をこのセッションで自分で実行する。
- `research/auto/` の下(state.json・ledger.tsv など)を手で書き換える。公開語の写し `research/auto/corpus/llms-full.txt` を読む(百万字を超える)。
- 本番に書き込む。一括登録・提案の取り込み・承認は人が管理画面で行う。
