# アプリ概要（最初に読むドキュメント）

新しく参加する開発者（および Claude Code セッション）が、素早く全体像を掴むための案内。
詳細は各リンク先を参照。方針・規約は [`CLAUDE.md`](../CLAUDE.md) が正。

## 1. コンセプト
- **日本語の単語を収集・解析・公開する Web アプリ**。
- 単語ごとに「読み・意味・ジャンル・品詞・言語学的特徴」などを構造化して蓄積し、
  読みの長さ・先頭/末尾文字・文字種パターン・リズム（ローマ字）・ジャンル階層などの
  多彩な軸で**検索・絞り込み**できるようにするのが目的。
- **公開方針**: 単語データの**閲覧は全世界に公開**。**登録・編集・削除は管理者(オーナー)のみ**。
- 想定規模: 1万レコード程度。

## 2. 技術スタック
- Ruby 3.4.2 / Rails 8.1
- MySQL 8.x（mysql2）※照合順序は `utf8mb4_0900_ai_ci` に統一（MySQL 8 専用）
- Puma / Hotwire(Turbo・Stimulus) / importmap-rails / Sprockets（ビルドツールは入れない方針）
- テスト: **Minitest**（`test/` 配下。RSpec は不使用）
- デプロイ: Capistrano（`cap production deploy`。後続で `deploy:seed` が自動実行）
- CI: GitHub Actions（PR作成時・main への push 時。DB は `mysql:8.4`）

## 3. 認証（管理者）
- Rails 8 標準の認証基盤（`has_secure_password` + セッション）。
- モデルは `Admin`、ログインは **`username`(ID) + パスワード**（メール不使用）。
- **サインアップ画面は無い**。管理者は `db/seeds.rb` が credentials か環境変数
  （`ADMIN_USERNAME` / `ADMIN_PASSWORD`）から作成/更新する。パスワード再設定(メール)機能は持たない。

## 4. ドメインモデル（全体像）
正は [`docs/schema.sql`](schema.sql)。関係の要点:
- `word` : `word_sense` = **1 : 多**（同音異義語に対応）。
- `genres` は**隣接リスト**（`parent_id`）で 大(level1)→中(level2)→小(level3) の3階層。
  `word_senses.genre_id` は**末端(小分類)のみ**を指し、中・大は `parent_id` を辿って一意に導出する。
  数値の分類コード列は持たない（名前＋階層のみ）。ジャンル一覧は [`docs/genres.md`](genres.md)。
- `linguistic_features` は中間表 `word_sense_features` 経由で語義と**多対多**。特徴は単語の**該当部分ごと**に付与する（`target`＝表層の一部 / `target_reading`＝その読み）。
- `entity_types` / `parts_of_speech` は単純マスタ（`name` のみ）。
- **生成カラム**: `reading_length` / `first_char` / `last_char` は SQL の STORED 生成カラム。
  `char_type_pattern`（漢/あ/ア/A/@）と `rhythm_pattern`（ローマ字）は **Ruby 側**で生成。

## 5. 実装状況（2026-07 時点）
段階的に実装中。計画とチェックリストは [`docs/issues.md`](issues.md)。
- ✅ Issue 1: 設計ドキュメント整備・スキーマ方針確定
- ✅ Issue 2: **ジャンル(genres)マスタ**（3階層・自己参照）… 本 branch `feature/add-genre` で実装
  - `app/models/genre.rb`（enum `level`、`self_and_ancestors` / `root_genre`、整合性バリデーション）
  - 大分類10件・中分類150件を seed 投入済み（カタログは `app/models/seed_catalog.rb`）
  - 既存 admins/sessions も `utf8mb4_0900_ai_ci` に統一済み
- ✅ Issue 3: **単純マスタ3種**（entity_types / parts_of_speech / linguistic_features）… `name` + `UNIQUE(name)` のみ
  - `parts_of_speech` は不規則複数形のため inflections に屈折ルールを追加
- ✅ Issue 4: words テーブル（surface / char_type_pattern 生成）
- ✅ Issue 5: **word_senses テーブル**（語義。word に 1:多）
  - STORED 生成カラム `reading_length` / `first_char` / `last_char`（SQL 側）
  - `rhythm_pattern` は値オブジェクト `RhythmPattern`（ヘボン式・長音は母音展開）で `before_validation` 自動生成
  - `genre_id` は小分類(level3)のみ許可するバリデーション
- ✅ Issue 6: **word_sense_features**（語義 × 言語学的特徴の多対多）
  - 特徴は単語の**該当部分ごと**に付与（`target`＝表層の一部 / `target_reading`＝その読み）。
    例:「硫黄島からの手紙」に 連濁:硫黄島 / 熟字訓:硫黄 / 連濁:手紙
  - 中間モデル `WordSenseFeature`、`UNIQUE(word_sense_id, linguistic_feature_id, target)` で三つ組の重複防止
  - `WordSense has_many :linguistic_features, through:` / `LinguisticFeature` も逆から辿れる（参照中は削除不可）
- ✅ Issue 7: **管理者用 CRUD**（`/admin/words`。認証必須の `Admin::` 名前空間）
  - Word→語義→特徴(該当部分つき)の1画面フル入れ子フォーム（`accepts_nested_attributes_for` ＋ Stimulus `nested-form`）
  - ジャンルは大→中→小の依存ドロップダウン（Stimulus `genre-cascade` ＋ `Admin::GenresController#children`）
- ✅ Issue 8: **公開閲覧**（一覧・詳細）
  - トップレベル `WordsController#index/#show` を `allow_unauthenticated_access` で開放（誰でも閲覧可）
  - 詳細で語義・ジャンル階層・品詞・特徴（該当部分つき）を表示。一覧は gem 無しの軽量ページネーション
- ✅ Issue 9: **検索・絞り込み**（公開 `GET /search`）
  - `reading_length`（範囲）/先頭・末尾文字/`char_type_pattern`/`rhythm_pattern`（部分一致）/ジャンル階層/品詞/エンティティタイプ/言語学的特徴
  - `WordSense` のスコープ群＋クエリオブジェクト `WordSenseSearch`。生成カラム/インデックスを活用
- ⬜ Issue 10: マスタのインライン追加（単語登録画面から完結）
- ✅ Issue 11: **拡張データ（読み指標・語種・別表記）** … データ層のみ（画面機能は別 Issue）
  - `word_senses` に `mora_count`（モーラ数・拗音は1拍）/ `vowel_pattern`（母音パターン）を追加。値オブジェクト `MoraCount` / `VowelPattern` ＋ `before_validation` で reading から生成
  - 語種マスタ `word_origins`（言語ごとに切り分け）＋ 語義との多対多 `word_sense_origins`（混種語対応）
  - 別表記 `word_sense_variants`（語義に 1:多、読みも保持）
  - バックフィルタスク `backfill:reading_metrics`
- ✅ Issue 12: **高速アノテーション・コンソール**（`/admin/annotations`）… 既存 `/admin/words` と併存
  - 1語集中キュー（`words.annotated_at` で未注釈を管理）。Turbo Frame で「保存して次へ」
  - ドロップダウン全廃・チップ選択（`:has()`）／ジャンル段階表示／特徴は文字の範囲タップ（`feature-range`）／マスタその場追加（`inline-add`・`genre-picker`）／語義複製（`sense-cloner`）

単語データは管理側の CRUD（`/admin/words`）・高速アノテーション（`/admin/annotations`）・公開閲覧（`/words`）・検索（`/search`）まで実装済み。マスタのその場追加はコンソールで実現済み（Issue 10 相当）。

## 6. 主要ファイル / ディレクトリ
- `app/models/` … `admin` / `session` / `current` / `genre` / `word` / `word_sense` / `word_sense_feature` /
  `entity_type` / `part_of_speech` / `linguistic_feature` / `word_origin` / `word_sense_origin`（語種の多対多）/
  `word_sense_variant`（別表記）/ 値オブジェクト `char_type_pattern` / `rhythm_pattern` / `mora_count` / `vowel_pattern` /
  `levenshtein`（読みの類似度）/ フォームオブジェクト `bulk_word_registration`（箇条書き一括登録の解析→登録）/
  クエリオブジェクト `word_sense_search`（検索条件の組み立て）
- `app/services/` … `reading_extractor`（MeCab CLI を Open3 で呼び、表層形→読みを自動取得）
- `app/controllers/` … `application_controller` / `home_controller` / `sessions_controller` /
  `words_controller`（公開閲覧の一覧・詳細）/ `searches_controller`（公開の検索・絞り込み）/
  `admin/`（`base` / `words` / `genres`。管理者専用 CRUD。名前空間 `Admin` は `Admin` モデルが保持）/
  `concerns/authentication.rb`（認証。閲覧公開は `allow_unauthenticated_access` で開放）
- `app/javascript/controllers/` … Stimulus。`nested_form`（行の動的追加/削除）/ `genre_cascade`（大中小の依存選択）/
  アノテーション用: `queue_nav`（キーボード送り）/ `inline_add`（マスタその場追加）/ `feature_range`（特徴の範囲タップ）/
  `genre_picker`（ジャンル段階表示＋その場追加）/ `sense_cloner`（語義の複製追加）
- `db/schema.rb` … スキーマの正（直接編集せずマイグレーション経由で更新）
- `db/seeds.rb` … 管理者とマスタを冪等に投入。マスタの名前リストとリネーム追従マップは
  `app/models/seed_catalog.rb` が単一の正（タグ統括管理の「seed」印と共有。運用ルールも同ファイル参照）
- `config/locales/ja.yml` … 既定ロケール `:ja`。表示文言はここに集約（ハードコードしない）
- `docs/` … `overview.md`(本書) / `schema.sql` / `issues.md` / `genres.md`

## 7. ローカル開発環境の立ち上げ（重要・非自明）
ローカルの MariaDB では `utf8mb4_0900_ai_ci` が使えないため、
**CI/本番と同じ MySQL 8.4 を Docker で用意**して接続する。
```bash
docker compose up -d          # MySQL 8.4 を起動（ホスト側ポート 3307。既存 3306 と競合回避）
bin/rails db:prepare          # DB 作成・マイグレーション・seed
bin/rails server              # 起動
```
- `config/database.yml` の development/test は既定で `127.0.0.1:3307` に接続
  （`DATABASE_HOST` / `DATABASE_PORT` で上書き可）。production は従来どおり socket + 環境変数。

### 一括登録（3ステップ）と読みの自動取得
- 管理者の一括登録（`/admin/words/new`）は3ステップ: **入力**（箇条書き）→ **読み**（step2）→ **重複**（step3）→ 登録。
  画面上部にフェーズ表示（`_steps.html.erb`）。重複判定は step2 で確定した読みに対して行う（誤読の取りこぼし防止）。
- step2 は箇条書きの表層形から **MeCab CLI** で読みを自動取得する
  （`app/services/reading_extractor.rb` が `mecab -Oyomi` を Open3 で呼ぶ）。
- 辞書は既定で **mecab-ipadic-neologd**。環境変数 `MECAB_DICT` でパスを上書き可。辞書が無ければ既定辞書へフォールバック。
- **mecab が未インストールの環境では読みは空欄**になり、確認画面で手入力する（機能は止まらない）。
- そのため **本番サーバ（Capistrano）と CI（GitHub Actions）で読みを自動取得するには、`mecab` 本体＋neologd 辞書の導入が別途必要**。
  テストは `ReadingExtractor.call` をスタブするため mecab 無しでも通る。

### 読み強化（オフライン調査 / アプリと切り離し）
- MeCab は誤読しうる（例「花は桜木人は武士」の 人＝ヒト を ジン と誤読）。これを独立ソースで正すため、
  **オフライン調査スキル** `.claude/skills/word-reading-research/` を用意（アプリの実行時には LLM/API を呼ばない方針）。
- 使い方: 別セッションの Claude Code に単語（表層形のみ）を渡すと、Web検索で裏取りして「最も一般的な表記＋読み（カタカナ）」を
  `schema.json` の形式で JSON 出力する。**MeCab の読みは入力に含めない**（追認バイアス回避）。
- 調査系スキル（`/notation`・`/reading`・`/annotation`）の入出力ファイルは `research/inputs`・`research/outputs`
  に置く（中身は gitignore 済み）。3つの流れは [`research/README.md`](../research/README.md) を参照。
- step2 の「調査結果（JSON）を反映」欄にその JSON を貼ると、MeCab の暫定読みと突き合わせて行ごとに
  一致／不一致／調査のみを表示し、候補チップ（Stimulus `reading-choice`）で読みを確定できる。
- 管理者は seed が credentials / 環境変数から作成する。ローカルで任意の値にするには:
  ```bash
  ADMIN_USERNAME=xxx ADMIN_PASSWORD=yyy bin/rails db:seed   # ローカル DB のみに反映
  ```

## 8. コミット前の必須チェック（CI と同一）
```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
bin/importmap audit
bin/rails test test:system
```

## 9. 進め方の規約
- **1 Issue = 1 ブランチ = 1 PR** を原則とする（[`docs/issues.md`](issues.md) 参照）。
- ブランチ名は `feature/<内容>`。**Issue/PR 番号は入れない**（Issue と PR で採番カウンタが共通のためズレる）。
- 返答・コミットメッセージ・コードコメントは日本語。
