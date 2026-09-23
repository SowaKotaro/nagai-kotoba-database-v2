# research/ — Claude Code のオフライン調査の作業ディレクトリ

`/harvest`・`/expand`・`/notation`・`/reading`・`/annotation` の5つのカスタムコマンド（それぞれ
`.claude/skills/word-*-research` スキルを起動する）が、**入力ファイルを読んで出力ファイルを書き出す**
という形で動く。その入出力を置く場所。

6つ目の `/reannotation`（1語の再調査）だけは、**JSON を会話に貼って起動し、結果もチャットに返す**
（スマートフォンから回すため）。ファイルは補助的に `outputs/reannotation.json` へ書くだけ。

`inputs/` と `outputs/` の中身は実行のたびに上書きされる作業ファイルなので、`.gitignore`
で除外している（ディレクトリだけ `.keep` で残す）。ローカルの状態ファイルも同様に除外:
`harvest-seen.txt`（/harvest が過去に提案した語の累積リスト）・`harvest-cron.log`（定期実行のログ）・
`.tmp-*`（途中経過の置き場）。**このディレクトリで git に載せるのは本 README だけ**という前提なので、
新しく作業ファイルを置くときは `.tmp-` で始まる名前にするか、`.gitignore` に足すこと。

## ファイルの対応

| コマンド | 入力 | 出力 |
| --- | --- | --- |
| `/harvest` | （外部サイトを巡回。入力ファイルなし） | `outputs/harvest/<実行日>-<セット>.txt` |
| `/expand` | `inputs/expansion.txt` | `outputs/expansion.txt`（人が読む版）＋ `outputs/expansion.json`（取り込み用） |
| `/notation` | `inputs/notation.txt` | `outputs/notation.txt`（人が読む版）＋ `outputs/notation.json`（取り込み用） |
| `/reading` | `inputs/reading.txt` | `outputs/reading.json` |
| `/annotation` | `inputs/annotation.json` | `outputs/annotation.json` |
| `/reannotation` | （会話に貼る再調査用JSON。無ければ `inputs/reannotation.json`） | チャットに提案JSON（＋`outputs/reannotation.json`） |

いずれも引数で入力パスを渡せば、上の既定パス以外も読める。

## 使う順番（候補収集 → 前処理 → 登録 → アノテーション）

登録前の語が「どこまで進んだか」は、ファイルではなく**管理画面「登録予定単語」（`/admin/candidates`）**の
ステータスで管理する。ファイルは実行のたびに上書きしてよい。スキルに渡すのは各段の画面の「書き出す」、
スキルの結果は同じ画面の「結果を取り込む」に貼る（語は書き出し時の ID `#123` で引くので、表記が変わっても崩れない）。

```
upload → expand → duplicate → notation → done（一括登録に貼る）→ 登録済み
（脇に外す: 要判断 / 重複 / 不要。不要にした語も消さずに残り、同じ語の再流入を防ぐ）
```

-1. **収穫（任意・定期実行向け）**: ニュースサイトなど更新頻度の高いサイトを巡回して、
   新しい候補語を外から拾う。`/harvest`（セットを指定するなら `/harvest 朝` `/harvest 夕`、
   系統を絞るなら `/harvest 美術` 等）。
   ソースは**朝セット**（エンタメ / ニュース / IT）と**夕セット**（スポーツ / 科学 / 学術 / 美術 /
   書籍 / ファッション）に分かれ、ジャンルが重ならないようにしてある。
   `outputs/harvest/<実行日>-<セット>.txt` の上部に候補語リストが並ぶので、目視で確認してから upload する。
   出力は日付＋セットごとに残る（確認前に次の実行が走っても流れない。取り込み済みの古い日付は適宜消してよい）。
   過去に提案済みの語は `harvest-seen.txt` で自動的に除外されるので、毎朝・毎夕の定期実行に耐える。
   cron で **7:17（朝セット）と 16:45（夕セット）**の1日2回動かしている。
0. **upload（ブラウザ）**: 1行1語で貼る。一覧で upload の語を見て、**expand に回す語**と
   **そのまま duplicate に回す語**を選ぶ。同じ系統の語（例: 泥門デビルバッツと王城ホワイトナイツ）は
   1つだけ expand に回すと、調査が重ならず `/expand` の負荷も抑えられる。要らない語は「不要」。
1. **expand（ローカル）**: expand の画面で書き出した内容を `inputs/expansion.txt` に保存して `/expand`。
   上位概念（作品・アーティスト等）を突き止め、**種語と同じエンティティ軸**の語を集める
   （泥門デビルバッツ → アイシールド21 の他のチーム名）。軸を変えたいときは引数で指定する（`/expand キャラクター名`）。
   `outputs/expansion.json` を同じ画面に貼ると、増えた語が元の語の下に並ぶ。要らない語は一覧で「不要」にしてから、
   「これらの語を一括で duplicate に変更」。
2. **duplicate（ブラウザ）**: 収録済みの語・別表記・ほかの登録予定単語と一致した語は最初からチェックされている。
   確認して「チェックした語を重複に、残りを一括で notation に変更」。
3. **notation（ローカル）**: notation の画面で書き出した内容を `inputs/notation.txt` に保存して `/notation`。
   `outputs/notation.json` を同じ画面に貼ると表記が置き換わる（立項スコア2以下は要判断、統一後に重なった語は重複、
   分割案は duplicate からやり直し）。確認して「これらの語を一括で done に変更」。
4. **読みと登録（いつもの一括登録）**: notation の画面の「done の語」をコピーし、`inputs/reading.txt` に置いて `/reading`。
   同じリストを一括登録 step1 に貼り、step2 で `outputs/reading.json` を「調査結果（JSON）を反映」欄に貼って
   MeCab の暫定読みと突き合わせ、step3（重複チェック）を経て登録する。登録された語は自動で「登録済み」になる。
5. **注釈**: 管理画面の「調査用データの書き出し」で得た JSON を `inputs/annotation.json` に保存し、
   `/annotation`。`outputs/annotation.json` を「提案 JSON の取り込み」に貼ると DB に下書きとして入り、
   アノテーション・コンソールで人間が承認する。
6. **再注釈（1語ずつ・随時）**: 5 の承認作業中に「この注釈は微妙だ」と思ったら、その語のコンソール
   画面（`/admin/annotations/:id`）の「再調査用JSON →」でコピーし、`/reannotation` の後ろに貼って起動する。
   調べ直す項目（意味・ジャンル・エンティティ・品詞・語種・言語的特徴・別表記・立項スコア）を
   選択肢で聞かれるので選ぶと、その項目だけを調べ直した提案JSONがチャットに返る。それを
   「提案 JSON の取り込み」に貼ると下書きが上書きされ、コンソールで承認し直せる。
   スマートフォンの Claude アプリからも同じ流れで回せる。

判断基準（立項の4原則・表記・読み・ジャンル選定）は [`docs/annotation-guidelines.md`](../docs/annotation-guidelines.md) が正。

## 共通の約束

- **でっち上げ厳禁**。記憶で語や読みを並べず、必ず WebSearch / WebFetch で裏を取り、
  確認できた分だけを出す。確信が持てないものは `confidence` を下げて候補を併記する。
- **アプリの実行時には LLM も外部 API も呼ばない**。調査はすべてこのオフラインの流れに閉じ、
  結果だけを人間が承認して DB に入れる（`annotated_at` を立てるのは人間だけ）。
- **MeCab の読みは `/reading` の入力に含めない**（追認バイアスを避けるため）。突き合わせは
  一括登録 step2 の画面で行う。
