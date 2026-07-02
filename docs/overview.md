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
  - 大分類10件・中分類150件を seed 投入済み（`db/seeds/genres.rb`）
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
- ⬜ Issue 7: 管理者用 CRUD（大→中→小のカスケード選択 UI）
- ⬜ Issue 8: 公開閲覧（一覧・詳細）
- ⬜ Issue 9: 検索・絞り込み

現状のアプリ本体は認証（`Admin` / `Session`）とルート(`home#index`)まで。単語系の画面は未実装。

## 6. 主要ファイル / ディレクトリ
- `app/models/` … `admin` / `session` / `current` / `genre`
- `app/controllers/` … `application_controller` / `home_controller` / `sessions_controller` /
  `concerns/authentication.rb`（認証。閲覧公開は `allow_unauthenticated_access` で開放）
- `db/schema.rb` … スキーマの正（直接編集せずマイグレーション経由で更新）
- `db/seeds.rb` → `db/seeds/genres.rb` … 管理者とジャンルマスタを冪等に投入
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
