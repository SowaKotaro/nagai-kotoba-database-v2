# research/ — Claude Code のオフライン調査の作業ディレクトリ

`/notation`・`/reading`・`/annotation` の3つのカスタムコマンド（それぞれ
`.claude/skills/word-*-research` スキルを起動する）が、**入力ファイルを読んで出力ファイルを書き出す**
という形で動く。その入出力を置く場所。

`inputs/` と `outputs/` の中身は実行のたびに上書きされる作業ファイルなので、`.gitignore`
で除外している（ディレクトリだけ `.keep` で残す）。

## ファイルの対応

| コマンド | 入力 | 出力 |
| --- | --- | --- |
| `/notation` | `inputs/notation.txt` | `outputs/notation.txt` |
| `/reading` | `inputs/reading.txt` | `outputs/reading.json` |
| `/annotation` | `inputs/annotation.json` | `outputs/annotation.json` |

いずれも引数で入力パスを渡せば、上の既定パス以外も読める。

## 使う順番（登録 → アノテーション）

1. **表記**: 集めた単語候補を1行1語で `inputs/notation.txt` に貼り、`/notation`。
   `outputs/notation.txt` の上部に、最も一般的な表記のリストが並ぶ。
2. **読み**: 1 のリストをそのまま `inputs/reading.txt` に置き、`/reading`。
   `outputs/reading.json` を、単語登録 step2「調査結果（JSON）を反映」欄に貼る。
   MeCab の暫定読みと突き合わせて確認・修正し、step3（重複チェック）を経て登録する。
3. **注釈**: 管理画面の「調査用データの書き出し」で得た JSON を `inputs/annotation.json` に保存し、
   `/annotation`。`outputs/annotation.json` を「提案 JSON の取り込み」に貼ると DB に下書きとして入り、
   アノテーション・コンソールで人間が承認する。

判断基準（立項の4原則・表記・読み・ジャンル選定）は [`docs/annotation-guidelines.md`](../docs/annotation-guidelines.md) が正。
