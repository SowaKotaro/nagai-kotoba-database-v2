---
description: 1語のアノテーションを項目を選んで調べ直す（word-reannotation-research スキル）
argument-hint: "[アノテーション・コンソールの「再調査用JSON」を貼る]"
---

`word-reannotation-research` スキルを**明示的に**使って再調査を実行してください。
似た名前の `word-annotation-research`（まとめての下調べ）とは**取り違えないこと**
（判断基準としては読みますが、起動するのは再調査スキルです）。

- 引数（貼られた再調査用JSON、またはファイルパス）: $ARGUMENTS
- 引数が JSON ならそれを入力にする。ファイルパスならそのファイル。空なら `research/inputs/reannotation.json`。
  どれも無ければ**その場で聞く**（勝手に語を探しに行かない）。
- `.claude/skills/word-reannotation-research/SKILL.md` の手順に厳密に従うこと。特に:
  - **調べ直す項目を AskUserQuestion で必ず確認してから**調査を始める（勝手に全項目やり直さない）。
  - 現在値は答え合わせの相手。**先に自力で調べてから突き合わせる**（アンカリング回避）。
  - **選ばれなかった項目は1文字も変えずに素通し**する。取り込みは payload を丸ごと上書きするため、
    出力は語の全項目が揃った完全な提案 JSON にする。
  - 出力は**チャットに JSON のコードブロック1つだけ**（携帯からコピーして「提案 JSON の取り込み」に貼る）。
    書ける環境なら `research/outputs/reannotation.json` にも同じ内容を書き出す。

まず Skill ツールで `word-reannotation-research` を起動してください。
