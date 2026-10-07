# データモデル

テーブルの関係と、スキーマに込めた設計判断をまとめる。

> **カラム定義の正は `db/schema.rb`**（マイグレーション経由で更新する。直接編集しない）。
> 本書はカラムを一覧しない。列挙するとスキーマが動くたびに二重管理になり、必ず片方が古くなるため。
> 「なぜそうなっているか」だけをここに置き、「どうなっているか」は `db/schema.rb` を見る。
>
> `db/migrate` の各ファイルのコメントは、書いた当時の記録である。後から名前や方針が変わっても
> 直していないので（マスタの名前・参照先の見出し・理由づけが古いままのものがある）、現行の仕様の正は
> `db/schema.rb` と本書にする。最初の 2 本（`20260629132054_create_articles.rb` と
> `20260630152904_drop_articles.rb`）は、初期に Rails の雛形を試したときのもので、いまの仕様とは関係が無い。

---

## 1. 全体の関係

```
admins ──< sessions                         管理者認証（Rails 8 標準）

words ──< word_senses                       表層形 1 : 多 語義（同音異義語）
  │          ├─ genre_id ──────> genres     小分類（末端）を指す。親を辿って中・大
  │          ├─ entity_type_id ─> entity_types
  │          ├─ part_of_speech_id > parts_of_speech
  │          ├──< word_sense_features ──> linguistic_features   多対多（該当部分ごと）
  │          ├──< word_sense_origins  ──> word_origins          多対多（混種語）
  │          └──< word_sense_variants                           別表記（読みも持つ）
  └─ has_one annotation_proposal            Claude Code の調査結果（下書き・語に 1 件）

word_requests ──< word_request_items        公開側からの収録リクエスト（1 通 : 多 語）

word_candidates ──> word_candidates (seed_id) 登録予定単語（/expand で生えた語は元の語を指す）
                ──> words (word_id)           登録済みになった語

genres ──< genres (parent_id)               大 → 中 → 小 の隣接リスト（自己参照）
```

- **想定規模は 1 万レコード程度**。集計はインデックス済みカラムへの `GROUP BY` と
  `Rails.cache` で足り、集計テーブルは作らない方針。
- すべて InnoDB / utf8mb4 / MySQL 8 系。

---

## 2. 主要テーブルの役割

| テーブル | 役割 |
|---|---|
| `words` | 表層形（見出し語）。1 語に複数の語義がぶら下がる。並び替え・ランキングの代表値もここに持つ（§5） |
| `word_senses` | 語義。読みと、読みから導いた各種指標を持つ。同音異義語はここで分ける |
| `genres` | ジャンル（大→中→小の3階層・自己参照）。一覧は [`genres.md`](genres.md) |
| `entity_types` / `parts_of_speech` / `linguistic_features` / `word_origins` | `name` と `UNIQUE(name)` だけの単純マスタ |
| `word_sense_features` | 語義 × 言語学的特徴。**単語の「該当部分」ごと**に付ける（§4） |
| `word_sense_origins` | 語義 × 語種。混種語（例: 歯ブラシ ＝ 日本語 ＋ 英語）を表すため多対多 |
| `word_sense_variants` | 別表記。語義に 1 : 多。読みも変わりうるので `reading` を持つ |
| `annotation_proposals` | Claude Code の調査結果の下書き。`payload`（JSON）と `status`。語に 1 件（`UNIQUE(word_id)`） |
| `word_requests` / `word_request_items` | 公開側からの収録リクエスト。通（送信 1 回 ＋ IP・UA・リファラー）と語（1 件 ＋ 状態）に分ける |
| `word_candidates` | 登録予定単語。登録前の前処理（仕分け → 拡張 → 表記 → 登録待ち → 登録済み）で、語が「次に何を待っているか」を `status` で持つ（仕分け待ち / 拡張待ち / 表記待ち / 表記の確認待ち / 登録待ち / 登録済み。脇に 保留 / 重複 / 不要）。/expand で集めた語は `seed_id`（元の語）と `root_id`（系統の根）を持ち、画面では元の語の系統として括って並ぶ。`expanded_at` は「拡張の元にして結果を取り込んだ」印、`notated_at` は /notation の結果を取り込んだ印（採用したとき表記待ちを飛ばして登録待ちへ進めるかをこれで決める）。不要にした語も消さず、`UNIQUE(surface)` で「一度見た語」の集合を兼ねる |
| `admins` / `sessions` | 管理者認証（`has_secure_password` ＋ セッション。ログインは `username`） |

### 語種は「外来語」で束ねない

`word_origins` は 日本語 / 英語 / フランス語 … と**言語ごとに切り分ける**開いた集合にしてある。
「外来語」でひとまとめにすると、このデータベースの見どころである語源の分布が潰れるため。
1 語義に複数の語種を付けられるので、混種語もそのまま表現できる。

---

## 3. 派生値をどこで作るか

読み・表層形から機械的に決まる値は**すべて自動生成**し、人に入力させない。作る場所は 3 通りある
（SQL の STORED 生成カラム／Ruby の値オブジェクト ＋ `before_validation`／`after_commit` で焼き直す代表値）。
**派生値の一覧・依存関係・直し方の正はこの節**で、CLAUDE.md からはここを参照する。

### 3.1 一覧

| カラム | 作る場所 | 依存する値 | 直接 UPDATE したあとの直し方（§3.4） | `backfill:verify` |
|---|---|---|---|---|
| `word_senses.reading_length` | STORED `CHAR_LENGTH(reading)`（「きゃ」は 2 文字として数える） | `reading` | 不要（DB が追従する） | 見ない（常に整合） |
| `word_senses.first_char` | STORED `LEFT(reading, 1)` | `reading` | 不要 | 見ない |
| `words.surface_length` | STORED `CHAR_LENGTH(surface)` | `surface` | 不要 | 見ない |
| `words.reading_density` | STORED `max_reading_length / NULLIF(CHAR_LENGTH(surface), 0)`（1 字あたりの読みの長さ） | **`words.max_reading_length`（代表値）**・`surface` | 代表値を直すと追従する（`reading_metrics` か `sense_metrics`）。STORED でも、読みを直接 UPDATE しただけでは古いまま | `max_reading_length` を通して見る |
| `words.char_type_pattern` | Ruby `CharTypePattern`（`Word` の `before_validation`） | `surface` | 一括のタスクは無い。該当の `Word` を保存し直す | 見る |
| `word_senses.rhythm_pattern` | Ruby `RhythmPattern` | `reading` | `reading_metrics` | 見る |
| `word_senses.vowel_pattern` | Ruby `VowelPattern` | `rhythm_pattern` | `reading_metrics` | 見る |
| `word_senses.mora_count` | Ruby `MoraCount` | `reading` | `reading_metrics` | 見る |
| `word_senses.ring_crossing_count` | Ruby `KanaRing.crossing_count` | `reading`（と `KanaRow` の行の写像） | `reading_metrics` | 見る |
| `word_senses.last_char` | Ruby `LastChar`（§3.2 の例外） | `reading` | `reading_metrics` | 見る |
| `words` の代表値（`sense_count`・`variant_count`・`feature_count`・`min_*`・`max_*` の 14 列） | `after_commit` → `WordSenseMetrics.refresh!`（§3.3） | 語義の `reading`・`reading_length`・`mora_count`・`ring_crossing_count`、別表記と特徴の件数 | `sense_metrics`（`reading_metrics` も最後に全件焼き直す） | 見る（焼き直しと同じ式で突き合わせる） |

- 語義の読み由来の 5 つ（`rhythm_pattern`〜`last_char`）は `WordSense.reading_derivations` の 1 か所で作る。
  保存時の `before_validation`・`backfill:reading_metrics`・`backfill:verify` がそれを使うので、列を足すときはここに足す。
- 代表値の列とその式は `WordSenseMetrics::COLUMN_EXPRESSIONS` の 1 か所にあり、焼き直し（UPDATE）と verify が共有する。
- `KanaRow` の写像（濁音を清音の行に入れる、など）を変えたら、保存済みの `ring_crossing_count` を `reading_metrics` で作り直す。

### 3.2 Ruby で作る理由

SQL では書けない（または書くと副作用がある）ため Ruby 側で作る。

| カラム | なぜ SQL にしないか |
|---|---|
| `words.char_type_pattern` | 文字種の判定規則が複雑。仕様は [`char_type_pattern.md`](char_type_pattern.md) |
| `word_senses.rhythm_pattern` | ヘボン式ローマ字化。仕様は [`rhythm_pattern.md`](rhythm_pattern.md) |
| `word_senses.vowel_pattern` | 上と同じ理由。`rhythm_pattern` の後に作る |
| `word_senses.mora_count` | 拗音を 1 拍に畳む規則が SQL で書けない |
| `word_senses.ring_crossing_count` | 弦の総当たり交差判定は SQL で書けない |
| `word_senses.last_char` | **下記の例外** |

> **`last_char` だけは「本当は生成カラムにしたい」例外**。末尾の長音符「ー」を飛ばして直前の
> 文字を採る必要があり、生成式にマルチバイト文字（`ー`）が入ると ActiveRecord の SchemaDumper
> （mysql2 アダプタ）が `schema.rb` を書き出すときに文字化けする既知の制限があるため、
> **通常カラム ＋ Ruby 側計算**にしてある（`app/models/last_char.rb`）。

### 3.3 `after_commit` で焼き直す非正規化の代表値

`words` の `min_*` / `max_*` / `sense_count` / `variant_count` / `feature_count` は
語義側から集計した代表値（§5）。`WordSense` / `WordSenseVariant` / `WordSenseFeature` の
`after_commit`（`RefreshesWordMetrics`）が `WordSenseMetrics.refresh!` を呼んで焼き直す。
焼き直しは `words.updated_at` を進めない（表示内容を変えないので、詳細ページの ETag や sitemap の版を動かさない）。

### 3.4 直接 UPDATE したあとの直し方

`update_all` や生 SQL で `reading` / `surface` を書き換えると、コールバックを通らないので、
§3.1 で「直し方」が「不要」以外の値が古いまま残る。

```bash
bin/rails backfill:verify          # 差分の検出だけ（読み取り専用）。語義の読み由来の値・char_type_pattern・words の代表値を見る
bin/rails backfill:reading_metrics # 読み由来の派生値を再生成し、最後に words の代表値も全件焼き直す
bin/rails backfill:sense_metrics   # words の代表値だけを全件焼き直す
```

`words.char_type_pattern` は一括で直すタスクが無いので、verify が挙げた `Word` を保存し直す
（`before_validation` で作り直す）。どのタスクも `words.updated_at` を進めないので、詳細ページの ETag や
sitemap の版は動かない。

---

## 4. 言語学的特徴は「該当部分ごと」に付ける

`word_sense_features` は語義に特徴を貼るだけでなく、**単語のどの部分がその特徴なのか**を持つ。

- `target` … 表層形の部分文字列（例: 硫黄島）
- `target_reading` … その部分の読み（例: イオウジマ）
- `target_start` … 表層形の先頭からの文字オフセット（0 始まり）

例:「硫黄島からの手紙（イオウジマカラノテガミ）」には 連濁:硫黄島 / 熟字訓:硫黄 / 連濁:手紙 が付く。

一意制約は **`(word_sense_id, linguistic_feature_id, target, target_start)`** の四つ組。
`target_start` を含めるのは、**同じ文字列が 1 語の中に複数回現れる**ことがあるため
（`target` だけの三つ組だと 2 回目が保存できない）。

特徴マスタの名前と定義（用語解説）は `config/linguistic_features_glossary.yml` が単一の正で、
アノテーション・コンソールの「用語解説」パネルが同じファイルを読む。

---

## 5. 並び替え・ランキングの指標は `words` に非正規化する

一覧の並び替えとランキングは、かつて `ORDER BY` の中で `word_senses` への相関サブクエリを
評価していた。これは `LIMIT 100` でも公開語の全件でサブクエリが走り、さらに filesort まで
通るため、**語数に正比例して重くなっていた**。

そこで代表値を `words` のカラムに落とし、「指標 ＋ id」の複合インデックス（降順の指標には
降順インデックス）を張って、`ORDER BY … LIMIT` を索引走査だけで解けるようにした。

- 昇順の並びは**最小**、降順の並びは**最大**を代表にする（「読みが長い順」は最長の語義で並ぶ）。
- 代表読み（`min_reading` / `max_reading` / `min_reversed_reading`）は 255 字まで。
  utf8mb4 の 255 字 = 1020 バイトなら prefix ではない全長インデックスを張れる
  （**prefix インデックスは `ORDER BY` に使えない**）。
- 文字を数える指標（小書きのかな・濁点・長音符）は `COLLATE utf8mb4_bin` に落として数える。
  照合順序（§6）の同一視に、数え方を左右させないための備え。2026-10-03 の実測では、`REPLACE` と
  `REGEXP_REPLACE` は、かな（小書きの ャ・濁点の バ で確認）については as_ci のままでも bin と同じ結果だった。
  照合順序で結果が変わったのは、`REGEXP_REPLACE` の大文字・小文字の区別だけ。

計測と経緯は [`history/performance-report.md`](history/performance-report.md) §3。

---

## 6. 照合順序（collation）

**テーブルの既定は `utf8mb4_0900_ai_ci`**。日本語検索が中心なので、ひらがな⇔カタカナ・
全角⇔半角・大文字⇔小文字を同一視できる照合を基準にする。

**ただし、読み・表層形まわりのカラムだけは `utf8mb4_0900_as_ci`（アクセント区別）** にする。
`ai_ci` は濁点・半濁点まで同一視して **ハ = バ = パ** になってしまい、読みの検索・索引・
しりとりが成立しないため。`as_ci` なら清濁を区別しつつ、ひらがな⇔カタカナ・A⇔a の同一視は残る。
**小書きと並字（ヤ⇔ャ、ツ⇔ッ）は、`as_ci` でも同一視される**（清濁と違って区別しない）。

それぞれの照合順序が何を同一視するかの実測（docker の開発用 MySQL 8.4 で、文字列リテラルどうしを比べた。
2026-09-27 と 2026-10-02 に計測）:

| 比較 | `utf8mb4_0900_as_ci` | `utf8mb4_0900_ai_ci` |
|---|---|---|
| ハ / バ（清濁） | 区別する | 同一視する |
| ヤ / ャ、ツ / ッ（小書き） | 同一視する | 同一視する（ヤ / ャ で計測） |
| あ / ア（ひらがな・カタカナ） | 同一視する | 同一視する |
| ア / ｱ（全角・半角のカナ） | 同一視する | 同一視する |
| Ａ / A（全角・半角の英字） | 同一視する | 同一視する |
| A / a（大文字・小文字） | 同一視する | （未計測） |
| ー / -（長音符・ハイフン） | 区別する | （未計測） |
| 「名詞␣」/「名詞」（末尾の空白） | 区別する | 区別する（0900 系の照合順序は NO PAD） |

`as_ci` にしてあるカラム:

| テーブル | カラム |
|---|---|
| `words` | `surface` / `max_reading` / `min_reading` / `min_reversed_reading` |
| `word_senses` | `reading` / `first_char` / `last_char` |
| `word_sense_variants` | `surface` / `reading` |
| `word_request_items` | `surface` / `reading` |
| `word_candidates` | `surface` / `original_surface` |

- 生成カラムの照合順序は表の既定に従うため、`first_char` のように**明示が要る**。
- 新しく読み・表層形を持つカラムを足すときは、**`as_ci` を明示すること**（忘れると清濁が畳まれる）。
- **一意制約にも、同じ同一視が効く**。たとえば `words.surface` の UNIQUE（as_ci）では、かなの種類・小書き・
  全角半角だけが違う表層形は、同じ語として重複エラーになる（清濁が違えば別の語）。
- 次のカラムは **`ai_ci` のまま**（表の既定）で、清濁も同一視する。
  - `word_sense_features.target` / `target_reading`（該当部分。一意制約 `uq_wsf_sense_feature_target_start` にも効く）
  - `words.char_type_pattern`（文字種の記号列）。大文字と小文字に加えて、**ひらがなの記号「あ」と
    カタカナの記号「ア」も同一視する**ので、区別せずに検索すると「あ」で「ア」も当たる。
    大文字・小文字（と「あ」「ア」）を区別するときだけ、クエリ側で `COLLATE utf8mb4_bin` に落とす
    （`WordSense.char_type_pattern_matching`）。
  - マスタの名前（ジャンル・語種・品詞・エンティティ種別・言語学的特徴）。一意制約も ai_ci なので、
    **清濁だけが違う名前は作れない**（ジャンルは、同じ親の下で）。末尾の空白は区別されるので、
    前後に空白の付いた別の名前はできうる。

### Ruby 側で照合順序に頼っている所

照合順序を変えるときは、次も一緒に確かめる。DB の同一視をそのまま使っているか、Ruby で真似ている。

| 場所 | 頼り方 |
|---|---|
| `WordCandidate.register_for!` | `where(surface:)` で引くので as_ci の同一視が効く。一括登録で収録した語と、かなの種類・全角半角・大文字小文字だけが違う登録予定単語も「登録済み」になる |
| `WordCandidate.matching`（すべての語の検索） | LIKE も as_ci で比べる（かなの種類・大文字小文字を問わない） |
| `Admin::WordRequestsController#registered_surfaces_for` | 収録済みの語を as_ci で集める。ただしビューは、集めた表層形（収録語の表記）とリクエストの表記を Ruby で完全一致で比べるので、かなの種類だけが違うリクエストには「収録済み」の印が付かない（既知の不具合。refactoring の台帳の受付箱 2026-10-07） |
| `WordRequestDuplicateCheck` | 照合キーを `KanaFold.to_katakana` で畳み、as_ci に寄せて Ruby で比べる（清濁は畳まない） |
| `WordsHelper#matched_variants`（別表記だけが一致した印） | ひらがな⇔カタカナと大文字小文字だけを畳む。DB の as_ci は全角・半角のカナも同一視するので、半角カナのキーワードでは印がずれうる（検索結果は変わらない） |
| `InlineMasterCreatable`（マスタのその場追加） | マスタ名の一意制約（ai_ci）で衝突したとき、清濁・かなの種類・大文字小文字だけが違う既存の名前を、理由として返す |

### prefix インデックス

utf8mb4 のインデックスキー長制限（3072 バイト）に収めるため、長い文字列カラムは先頭 191 文字で
索引する（`surface(191)` / `reading(191)` / `char_type_pattern(191)` / `vowel_pattern(191)` /
`target(191)` など）。`words.surface` の UNIQUE も prefix なので、**先頭 191 文字が同一の
長文語は DB エラーになる**（現実的には起きないが、既知の割り切り。`history/changelog.md` Issue 56）。

---

## 7. 整合性をどこで担保するか

- **モデルと DB 制約の両方**で担保する（`NOT NULL` / `UNIQUE` ＋ `validates`）。
- `word_senses.genre_id` が**小分類だけ**を指すのはモデルのバリデーション（`genre_must_be_small`）
  で、**DB 側の制約は無い**。現状の書き込み経路はすべてモデルを通るので安全だが、
  直接 UPDATE では中・大分類が入りうる（`history/changelog.md` Issue 56）。
- マスタは参照中に削除できない（`dependent: :restrict_with_error`）。タグ統括管理
  （`/admin/tags`）の削除ガードもこれを使う。
- 複数レコードの整合性が要る更新は `transaction` でまとめる（ジャンルの統合など）。

**片側だけで担保しているもの**（`db/schema.rb` の `null: false`・`unique: true` と、各モデルの `validates`・`validate` を突き合わせた。
両側にあるものは載せない）:

| テーブル | DB だけ | モデルだけ |
|---|---|---|
| `admins` | `username` の NOT NULL・UNIQUE（モデルは前後の空白を落として小文字にするだけ。管理者は seed だけが作る） | — |
| `annotation_proposals` | `word_id` の UNIQUE（1 語に提案 1 件。取り込みは同じ語の提案を上書きする） | — |
| `genres` | — | 親と階層の整合（`parent_matches_level`）。大分類（`parent_id` が NULL）どうしの同名は、DB の UNIQUE では防げない（NULL は重複とみなされない）のでモデルが防ぐ |
| `word_senses` | — | `genre_id` が小分類だけを指すこと（`genre_must_be_small`。上記） |
| `word_sense_features` | — | 該当部分が表層形・読みの中にあること（`target_within_surface`・`target_reading_within_reading`） |
| `word_candidates` | — | メモの長さ・立項スコアの範囲・確信度の語彙 |
| `word_requests`・`word_request_items` | — | 1 通あたりの語数の上限・各欄の文字数の上限 |
| `words` | `surface` の UNIQUE は先頭 191 文字の prefix（§6） | — |

`status` などの enum の列は、DB が NOT NULL を持ち、モデルは enum の値の範囲だけを見る（`WordCandidate` は `validate: true` で検証エラーにする。
ほかは、範囲外の値を代入すると例外になる）。派生値の列の NOT NULL（`words.char_type_pattern` など）は、`before_validation` と既定値で埋まる（§3）。

---

## 8. 公開と未公開の境目

- **公開されるのは `words.annotated_at` が立っている語だけ**（`Word.annotated` / `WordSense.published`）。
  語を出す公開出力（一覧・検索・sitemap・API・統計）は、原則としてこのスコープを通る。
  例外は下の表の 3 つで、どれも未公開の語そのものを出すものではない。
- `annotated_at` は「注釈を終えて公開した日時」＝**収録日**として、公開面の日付・並び順に使う。
  `created_at` は一括登録で下書きを作った日時でしかなく、公開日とは何日もずれるため使わない。
- `annotation_status`（未対応 / 保留 / 完了）はアノテーション作業のキュー管理用。完了は
  `annotated_at` ありと一致するが、公開判定は `annotated_at` の側で行う。

### 8.1 スコープを通らない公開出力

| 出力 | 何を読むか | 語の漏れにならない理由と、注意 |
|---|---|---|
| 統計ページ §1 のワードクラウド | コミット済みの事前集計ファイル `db/morpheme_frequencies.json`（`MorphemeFrequencies`） | 生成（`bin/rails stats:morphemes`）は `Word.annotated` を通る。`SURFACES_FILE` を渡すときは公開語だけのファイルにする（`lib/tasks/stats.rake`）。載るのは 2 語以上に現れた部品（`MorphemeFrequencies::MIN_COUNT`）で、語そのものは出ない。生成した後に公開を取り消した語の部品は、作り直すまで残る |
| /search のフォームの選択肢と、一覧のファセットの見出し | マスタ（ジャンル・品詞・エンティティ・語種・特徴）の全件 | 出るのはマスタの名前だけで、語は出ない。ただし公開語に使われていない名前も出る（未公開の語のために作ったマスタの名前も出うる）。/genres は 0 件の分類を隠すので、画面によって見せ方が違う |
| ホームの「ジャンル数」 | `HomeStatistics` の `Genre.small.count`（マスタの小分類の全件） | 数だけで、語は出ない。公開語の有無を問わず数えるので、/genres のレールの数・統計の「使用ジャンル」とは定義が違う |

### 8.2 公開の取り消しが反映されるまで

公開済みの語を保留に戻す（`annotated_at` を空にする）か削除しても、キャッシュの有効期限のあいだは、
一部の公開出力にその語が残る（最大およそ 1 日）。性能のための意図的な割り切りで、オーナーが許容している（2026-10-03）。

- **すぐ消える**: 単語詳細・一覧・Atom・共有カード。どれもリクエストのたびに公開スコープを引く
  （HTTP キャッシュも条件付き GET で検証し直す）。ただし共有カードの PNG は、版付きの URL に
  1 年の `immutable` を宣言しているので、配った URL の画像はブラウザ・CDN・SNS に残る（サイトからはもう辿れない）。
- **最大 1 日残る（表層形・読み・意味を含む）**: `llms-full.txt` と `sitemap.xml`。版（`PublishedWordsDigest`）が
  「公開語の最終更新日」なので、語が減っても版が変わらない。`Cache-Control` でも 1 日の猶予を宣言している。
  /rankings（`WordRanking`）と /stats（`SiteStatistics`）も 1 日キャッシュで、表層形と読みを含む。
- **数だけ残る**: ホームの数（`HomeStatistics`。1 時間）、About の収録語数（`AboutStatistics`。1 日）、/genres・/browse の件数（`PublishedSenseCounts`。1 時間）。
- 本番のキャッシュはプロセス内のメモリ（`config.cache_store = :memory_store`）なので、Puma の再起動・デプロイで消える。
  すぐ消したいときは再起動する。

新しくキャッシュを足すときは、公開の取り消しがその有効期限のあいだ反映されないことを前提にする。
