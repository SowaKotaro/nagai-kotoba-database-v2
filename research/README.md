# research/ — Claude Code のオフライン調査の作業ディレクトリ

`/harvest`・`/expand`・`/notation`・`/reading`・`/annotation` の5つのカスタムコマンド（それぞれ
`.claude/skills/word-*-research` スキルを起動する）が、**入力ファイルを読んで出力ファイルを書き出す**
という形で動く。その入出力を置く場所。

6つ目の `/reannotation`（1語の再調査）だけは、**JSON を会話に貼って起動し、結果もチャットに返す**
（スマートフォンから回すため）。ファイルは補助的に `outputs/reannotation.json` へ書くだけ。

`inputs/` と `outputs/` の中身は実行のたびに上書きされる作業ファイルなので、`.gitignore`
で除外している（ディレクトリだけ `.keep` で残す）。`harvest-seen.txt`（/harvest が過去に
提案した語の累積リスト）もローカルの状態ファイルとして gitignore している。

## ファイルの対応

| コマンド | 入力 | 出力 |
| --- | --- | --- |
| `/harvest` | （外部サイトを巡回。入力ファイルなし） | `outputs/harvest/<実行日>-<セット>.txt` |
| `/expand` | `inputs/expansion.txt` | `outputs/expansion.txt` |
| `/notation` | `inputs/notation.txt` | `outputs/notation.txt` |
| `/reading` | `inputs/reading.txt` | `outputs/reading.json` |
| `/annotation` | `inputs/annotation.json` | `outputs/annotation.json` |
| `/reannotation` | （会話に貼る再調査用JSON。無ければ `inputs/reannotation.json`） | チャットに提案JSON（＋`outputs/reannotation.json`） |

いずれも引数で入力パスを渡せば、上の既定パス以外も読める。

## 使う順番（候補収集 → 登録 → アノテーション）

-1. **収穫（任意・定期実行向け）**: ニュースサイトなど更新頻度の高いサイトを巡回して、
   新しい候補語を外から拾う。`/harvest`（セットを指定するなら `/harvest 朝` `/harvest 夕`、
   系統を絞るなら `/harvest 美術` 等）。
   ソースは**朝セット**（エンタメ / ニュース / IT）と**夕セット**（スポーツ / 科学 / 学術 / 美術 /
   書籍 / ファッション）に分かれ、ジャンルが重ならないようにしてある。
   `outputs/harvest/<実行日>-<セット>.txt` の上部に候補語リストが並ぶので、目視で確認してから次の 1 の入力にする。
   出力は日付＋セットごとに残る（確認前に次の実行が走っても流れない。取り込み済みの古い日付は適宜消してよい）。
   過去に提案済みの語は `harvest-seen.txt` で自動的に除外されるので、毎朝・毎夕の定期実行に耐える。
   cron で **7:17（朝セット）と 16:45（夕セット）**の1日2回動かしている。
0. **補完（任意）**: 登録済みの語を種として、同系統の語をまとめて集めたいときに使う。
   種語を1行1語で `inputs/expansion.txt` に貼り、`/expand`。上位概念（作品・アーティスト等）を
   突き止め、**種語と同じエンティティ軸**の語を集める（泥門デビルバッツ → アイシールド21 の他のチーム名）。
   軸を変えたいときは引数で指定する（`/expand キャラクター名`）。
   `outputs/expansion.txt` の上部に候補語リストが並ぶので、そのまま次の 1 の入力にする。
1. **表記**: 集めた単語候補を1行1語で `inputs/notation.txt` に貼り、`/notation`。
   `outputs/notation.txt` の上部に、最も一般的な表記のリストが並ぶ。
2. **読み**: 1 のリストをそのまま `inputs/reading.txt` に置き、`/reading`。
   `outputs/reading.json` を、単語登録 step2「調査結果（JSON）を反映」欄に貼る。
   MeCab の暫定読みと突き合わせて確認・修正し、step3（重複チェック）を経て登録する。
3. **注釈**: 管理画面の「調査用データの書き出し」で得た JSON を `inputs/annotation.json` に保存し、
   `/annotation`。`outputs/annotation.json` を「提案 JSON の取り込み」に貼ると DB に下書きとして入り、
   アノテーション・コンソールで人間が承認する。
4. **再注釈（1語ずつ・随時）**: 3 の承認作業中に「この注釈は微妙だ」と思ったら、その語のコンソール
   画面（`/admin/annotations/:id`）の「再調査用JSON →」でコピーし、`/reannotation` の後ろに貼って起動する。
   調べ直す項目（意味・ジャンル・エンティティ・品詞・語種・言語的特徴・別表記・立項スコア）を
   選択肢で聞かれるので選ぶと、その項目だけを調べ直した提案JSONがチャットに返る。それを
   「提案 JSON の取り込み」に貼ると下書きが上書きされ、コンソールで承認し直せる。
   スマートフォンの Claude アプリからも同じ流れで回せる。

判断基準（立項の4原則・表記・読み・ジャンル選定）は [`docs/annotation-guidelines.md`](../docs/annotation-guidelines.md) が正。
