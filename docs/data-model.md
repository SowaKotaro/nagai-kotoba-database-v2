# データモデル

テーブルの関係と、スキーマに込めた設計判断をまとめる。

> **カラム定義の正は `db/schema.rb`**（マイグレーション経由で更新する。直接編集しない）。
> 本書はカラムを一覧しない。列挙するとスキーマが動くたびに二重管理になり、必ず片方が古くなるため。
> 「なぜそうなっているか」だけをここに置き、「どうなっているか」は `db/schema.rb` を見る。

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
| `admins` / `sessions` | 管理者認証（`has_secure_password` ＋ セッション。ログインは `username`） |

### 語種は「外来語」で束ねない

`word_origins` は 日本語 / 英語 / フランス語 … と**言語ごとに切り分ける**開いた集合にしてある。
「外来語」でひとまとめにすると、このデータベースの見どころである語源の分布が潰れるため。
1 語義に複数の語種を付けられるので、混種語もそのまま表現できる。

---

## 3. 派生値をどこで作るか

読み・表層形から機械的に決まる値は**すべて自動生成**し、人に入力させない。生成場所は 3 通りある。

### 3.1 SQL の STORED 生成カラム

`db/schema.rb` では `t.virtual ..., stored: true`。DB が値を保証するので、直接 UPDATE しても狂わない。

| カラム | 式 |
|---|---|
| `word_senses.reading_length` | `CHAR_LENGTH(reading)`（「きゃ」は 2 文字として数える） |
| `word_senses.first_char` | `LEFT(reading, 1)` |
| `words.surface_length` | `CHAR_LENGTH(surface)` |
| `words.reading_density` | `max_reading_length / NULLIF(CHAR_LENGTH(surface), 0)`（1 字あたりの読みの長さ） |

### 3.2 Ruby の値オブジェクト ＋ `before_validation`

SQL では書けない（または書くと副作用がある）ため Ruby 側で作る。

| カラム | 生成 | なぜ SQL にしないか |
|---|---|---|
| `words.char_type_pattern` | `CharTypePattern` | 文字種の判定規則が複雑。仕様は [`char_type_pattern.md`](char_type_pattern.md) |
| `word_senses.rhythm_pattern` | `RhythmPattern` | ヘボン式ローマ字化。仕様は [`rhythm_pattern.md`](rhythm_pattern.md) |
| `word_senses.vowel_pattern` | `VowelPattern`（`rhythm_pattern` から） | 上と同じ理由。`rhythm_pattern` の後に生成する |
| `word_senses.mora_count` | `MoraCount` | 拗音を 1 拍に畳む規則が SQL で書けない |
| `word_senses.ring_crossing_count` | `KanaRing.crossing_count` | 弦の総当たり交差判定は SQL で書けない |
| `word_senses.last_char` | `LastChar` | **下記の例外** |

> **`last_char` だけは「本当は生成カラムにしたい」例外**。末尾の長音符「ー」を飛ばして直前の
> 文字を採る必要があり、生成式にマルチバイト文字（`ー`）が入ると ActiveRecord の SchemaDumper
> （mysql2 アダプタ）が `schema.rb` を書き出すときに文字化けする既知の制限があるため、
> **通常カラム ＋ Ruby 側計算**にしてある（`app/models/last_char.rb`）。

### 3.3 `after_commit` で焼き直す非正規化の代表値

`words` の `min_*` / `max_*` / `sense_count` / `variant_count` / `feature_count` は
語義側から集計した代表値（§5）。`WordSense` / `WordSenseVariant` / `WordSenseFeature` の
`after_commit`（`RefreshesWordMetrics`）が `WordSenseMetrics.refresh!` を呼んで焼き直す。

### 3.4 直接 UPDATE したあとの直し方

`update_all` や生 SQL で `reading` / `surface` を書き換えると §3.2・§3.3 の値が古いまま残る。

```bash
bin/rails backfill:verify          # 差分の検出だけ（読み取り専用）
bin/rails backfill:reading_metrics # 読み由来の派生値を再生成
bin/rails backfill:sense_metrics   # words の代表値を全件焼き直す
```

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
  格納時の照合順序（§6）のままだと小書き⇔並字・清濁が畳まれて数を取り違えるため。

計測と経緯は [`performance-report.md`](performance-report.md) §3。

---

## 6. 照合順序（collation）

**テーブルの既定は `utf8mb4_0900_ai_ci`**。日本語検索が中心なので、ひらがな⇔カタカナ・
全角⇔半角・大文字⇔小文字を同一視できる照合を基準にする。

**ただし、読み・表層形まわりのカラムだけは `utf8mb4_0900_as_ci`（アクセント区別）** にする。
`ai_ci` は濁点・半濁点まで同一視して **ハ = バ = パ** になってしまい、読みの検索・索引・
しりとりが成立しないため。`as_ci` なら清濁を区別しつつ、ひらがな⇔カタカナ・A⇔a の同一視は残る。

`as_ci` にしてあるカラム:

| テーブル | カラム |
|---|---|
| `words` | `surface` / `max_reading` / `min_reading` / `min_reversed_reading` |
| `word_senses` | `reading` / `first_char` / `last_char` |
| `word_sense_variants` | `surface` / `reading` |
| `word_request_items` | `surface` / `reading` |

- 生成カラムの照合順序は表の既定に従うため、`first_char` のように**明示が要る**。
- 新しく読み・表層形を持つカラムを足すときは、**`as_ci` を明示すること**（忘れると清濁が畳まれる）。
- 文字種検索で大文字小文字を区別するときだけ、クエリ側で `COLLATE utf8mb4_bin` に落とす
  （`WordSense.char_type_pattern_matching`）。

### prefix インデックス

utf8mb4 のインデックスキー長制限（3072 バイト）に収めるため、長い文字列カラムは先頭 191 文字で
索引する（`surface(191)` / `reading(191)` / `char_type_pattern(191)` / `vowel_pattern(191)` /
`target(191)` など）。`words.surface` の UNIQUE も prefix なので、**先頭 191 文字が同一の
長文語は DB エラーになる**（現実的には起きないが、既知の割り切り。`issues.md` Issue 56）。

---

## 7. 整合性をどこで担保するか

- **モデルと DB 制約の両方**で担保する（`NOT NULL` / `UNIQUE` ＋ `validates`）。
- `word_senses.genre_id` が**小分類だけ**を指すのはモデルのバリデーション（`genre_must_be_small`）
  で、**DB 側の制約は無い**。現状の書き込み経路はすべてモデルを通るので安全だが、
  直接 UPDATE では中・大分類が入りうる（`issues.md` Issue 56）。
- マスタは参照中に削除できない（`dependent: :restrict_with_error`）。タグ統括管理
  （`/admin/tags`）の削除ガードもこれを使う。
- 複数レコードの整合性が要る更新は `transaction` でまとめる（ジャンルの統合など）。

---

## 8. 公開と未公開の境目

- **公開されるのは `words.annotated_at` が立っている語だけ**（`Word.annotated` / `WordSense.published`）。
  一覧・検索・sitemap・API・統計のすべてがこのスコープを通る。
- `annotated_at` は「注釈を終えて公開した日時」＝**収録日**として、公開面の日付・並び順に使う。
  `created_at` は一括登録で下書きを作った日時でしかなく、公開日とは何日もずれるため使わない。
- `annotation_status`（未対応 / 保留 / 完了）はアノテーション作業のキュー管理用。完了は
  `annotated_at` ありと一致するが、公開判定は `annotated_at` の側で行う。
