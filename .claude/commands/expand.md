---
description: 種語の上位概念を突き止め、同系統の単語をまとめて収集（word-expansion-research スキル）
argument-hint: "[任意: 収集軸の指定（例 キャラクター名）／入力ファイルパス／--out 出力ディレクトリ／--auto。既定は軸をスキルが調査・選定、research/inputs/expansion.txt]"
---

`word-expansion-research` スキルを**明示的に**使って調査を実行してください。
似た名前の `word-notation-research`（表記）・`word-reading-research`（読み）・
`word-annotation-research`（アノテーション）とは**取り違えないこと**。

- 引数: $ARGUMENTS
- 引数の解釈: `--out <ディレクトリ>` があれば、出力をそのディレクトリに書く。`--auto` があれば自動実行のモード（下記）。
  残りの引数が**ファイルパスに見えるなら入力パス**として使う。**それ以外の語句は収集軸**
  （例 `キャラクター名` `楽曲名` `必殺技名`）として使い、軸の選定をせずその軸で収集する。
  空なら既定（入力 `research/inputs/expansion.txt`／収集軸はスキルが調査して有望な軸を選定）。
- 出力ファイル: `expansion.txt` と `expansion.json`（どちらも上書き）。置き場所は `--out` のディレクトリ、無ければ `research/outputs/`（SKILL.md に書かれた `research/outputs/` の出力パスは、`--out` があればそのディレクトリに読み替える）。
  入力行頭の `#<数字>` は管理画面の ID なので、JSON の `id` にそのまま返すこと。
- `.claude/skills/word-expansion-research/SKILL.md` の手順に厳密に従うこと
  （上位概念の特定と収集軸の選定 → 実在する一覧を出典に列挙 → 4原則と**読み10文字以上（厳密）**でふるい分け →
  1種語×1軸あたり30語の上限 → 出典URL と confidence 付きの注記）。
- **読みの文字数は厳密に判定する**。全候補の読み（カタカナ）を決め、
  `bin/rails runner .claude/skills/word-expansion-research/reading_length.rb` で数えて、
  10文字未満は1文字足りないだけでも除外する（「際どいので残す」はしない）。読みが割れて決めきれない語も除外する。
  **`--auto` のときは数えない**（スクリプトを動かさない。Bash も使えない）。SKILL.md の「自動実行のモード」に従い、
  全候補の読みと系統の確信度を JSON に載せる（文字数のふるいは呼び出し側のコードが行う）。
  **有望な軸が無い種語は無理に拡張せず**、同系統語0件で理由を注記に書く。
- **種語自身も出力の候補リストに含める**（重複は、拡張の画面に取り込むときに管理画面が弾く）。
- **でっち上げ厳禁**。記憶で語を並べず、必ず WebSearch で一覧を確認し、確認できた分だけを出すこと。

まず Skill ツールで `word-expansion-research` を起動し、入力ファイルを読んで調査し、出力ファイルを書き出してください。
