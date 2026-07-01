# プロジェクト方針（nagai-kotoba-database-v2 / Claude Code 向け）

> **最初に読む**: アプリの全体像・実装状況・ローカル環境の立ち上げは [`docs/overview.md`](docs/overview.md) にまとめてある。新規セッションはまずこれを参照するとスムーズ。

## 言語・コミュニケーション
- 返答・コミットメッセージ・コードコメントは原則 **日本語** で記述する。

## このプロジェクトについて
- アプリ概要: **日本語の単語を収集・解析・公開する Web アプリ**。
- 公開方針: **単語データの閲覧は全世界に公開**（誰でも閲覧可）。**登録・編集・削除は管理者（オーナー）のみ**。
- 認証: 管理者認証は **Rails 8 標準の認証基盤**（has_secure_password + セッション）。モデルは `Admin`、ログインは **`username`(ID) + パスワード**（メールは使わない）。サインアップ画面は無く、管理者は `db/seeds.rb`（credentials/環境変数）で作成する。**パスワード再設定（メール）機能は持たない**。
- バージョン: **Ruby 3.4.2 / Rails 8.1**
- 構成: Rails + **MySQL（mysql2）** + Puma + Hotwire（Turbo / Stimulus）+ importmap-rails + Sprockets
- テスト: **Minitest**（`test/` 配下。RSpec は使っていない）
- デプロイ: **Capistrano**（`cap production deploy`）。本番 DB パスワードは環境変数 `NAGAI_KOTOBA_DATABASE_V2_PASSWORD`。デプロイ後に `deploy:seed` が自動実行される。
- CI: GitHub Actions（`.github/workflows/ci.yml`）。**PR 作成時** と **main への push 時** に実行。

## データモデル（詳細は `docs/schema.sql` / `docs/issues.md`）
- `word` : `word_sense` = **1 : 多**（同音異義語に対応）。
- `genres` は **隣接リスト**（`parent_id`）で 大→中→小 の3階層。`word_senses.genre_id` は末端（小分類）を指す。
- `linguistic_features` は `word_sense_features` 経由で語義と**多対多**。
- **生成カラム**: `reading_length`/`first_char`/`last_char` は SQL の STORED 生成カラム。`char_type_pattern`（漢/あ/ア/A/@）・`rhythm_pattern`（ローマ字）は **Ruby 側で生成**する。
- **照合順序**: 日本語検索が中心のため全テーブルを **`utf8mb4_0900_ai_ci`** に統一する方針。長い文字列カラムは prefix index（例 `surface(191)`）を使う。

---

## コミット前に必ず実行すること（強制チェック）
コードを変更したら、コミット前に以下を実行し、**指摘をすべて解消する**こと。CI と同じ内容なので、ローカルで通れば CI も通る。

```bash
bundle exec rubocop                      # スタイル / 静的解析（rubocop-rails-omakase）
bundle exec brakeman --no-pager          # セキュリティ静的スキャン
bundle exec bundler-audit check --update # gem 依存の既知脆弱性
bin/importmap audit                      # JS 依存の既知脆弱性
bin/rails test test:system               # テスト（単体 + システム）
```

- これらが通らないコードは「未完成」とみなす。エラーは握りつぶさず修正する。
- RuboCop は安全な範囲で `bundle exec rubocop -a` による自動修正を活用してよい。
- 機械的に検出できる項目（スタイル・既知の脆弱性・N+1 など）は自動チェックに任せ、
  本ファイルでは「機械では測りにくい設計・命名の観点」を中心に守る。

---

## セキュリティ（最優先）
- **Strong Parameters** を必ず使う。`params.require(...).permit(...)` で許可した属性のみ受け付ける。
- **SQL は必ずプレースホルダ**を使う。文字列展開でクエリを組まない。
  - NG: `Word.where("surface = '#{params[:q]}'")`
  - OK: `Word.where(surface: params[:q])` / `Word.where("surface = ?", params[:q])`
- **認可を徹底する**。閲覧（read）は全世界に公開だが、**登録・編集・削除は管理者のみ**。
  - 書き込み系アクションには認証必須の `before_action` を必ず付ける（管理者未ログインは弾く）。
  - 公開閲覧アクションは `allow_unauthenticated_access` で明示的に開放し、書き込み経路を漏らさない。
- ビュー出力は基本エスケープに任せる。`html_safe` / `raw` / `<%==` は安易に使わない。
- 機密情報をコードに直書きしない。`Rails.application.credentials`（`config/credentials.yml.enc`）か環境変数を使う。`config/master.key` はコミットしない。
- ログに個人情報・パスワード・トークンを出さない（`config.filter_parameters` を設定）。

## ActiveRecord / データベース
- **N+1 を作らない**。関連を辿るループの前に `includes` / `preload` / `eager_load` を使う（word→word_senses→各マスタは特に注意）。
- 外部キー・検索条件・ユニーク制約のカラムには **インデックス**を張る。
- バリデーションは **モデルと DB 制約の両方**で担保する（`NOT NULL` / `unique index` ＋ モデルの `validates`）。
- 複数レコードの整合性が必要な更新は `transaction` でまとめる。
- マイグレーションはロールバック可能に書く。`change` で表現できない処理は `up` / `down` を定義する。
- スキーマは `db/schema.rb` が正。直接編集せずマイグレーション経由で更新する。
- MySQL（utf8mb4 / `0900_ai_ci`）前提。文字数・絵文字・照合順序に注意する。STORED 生成カラムは `t.virtual ..., stored: true` で定義する。
- 大きなテーブルへの変更（カラム追加・インデックス・ロック）は本番への影響を一言添える。

## 設計・アーキテクチャ
- **Fat Controller / Fat Model を避ける**。コントローラはリクエストの受け渡しに徹する。
- ビジネスロジック（`char_type_pattern`・`rhythm_pattern` の生成など）が膨らんだら Service Object / Value Object / Concern に切り出す（`app/models/concerns`・`app/controllers/concerns` を活用）。
- `before_save` などのコールバックに、外部 API 通信や重い副作用を詰め込まない。
- 既存の Rails / Gem の機能で済むものを自作しない。**Rails の規約（CoC）に沿う**。
- フロントは Hotwire（Turbo / Stimulus）+ importmap 構成。ビルドツール（webpack 等）は導入しない方針。JS は最小限に。

## 重い処理・外部連携
- メール送信・外部 API 呼び出し・重い集計は **ActiveJob で非同期化**する。
- 現状バックグラウンドジョブのバックエンドは未導入（既定の `:async` アダプタで、プロセス内実行）。
  恒常的なジョブ基盤が必要になったら、Rails 8 標準の **Solid Queue** 導入を第一候補として検討・相談する。
- ジョブは**冪等**に設計し、リトライされても問題ないようにする。
- 外部 API 呼び出しには **タイムアウトと例外処理**を必ず入れる。

## 可読性・命名
- メソッド・変数・クラス名は**意図が伝わる名前**にする。省略しすぎない。
- マジックナンバー / マジック文字列は定数化、状態は Enum 化する（`genres.level` など）。
- 重複は適度に DRY にする。ただし過度な抽象化は避け、読みやすさを優先する。
- 表示文言は `config/locales`（既定ロケールは `:ja`、`ja.yml`）の i18n（`t(...)`）を使い、ハードコードしない。

## テスト（Minitest）
- 変更には対応するテストを用意する。**正常系だけでなく異常系・境界値**も書く（例: `char_type_pattern` 変換の記号・数字・全角半角）。
- 種類を目的に応じて使い分ける: モデル（`test/models`）/ コントローラ・結合（`test/controllers`・`test/integration`）/ システム（`test/system`、Capybara + Selenium）。
- フィクスチャは `test/fixtures` を使う。
- 過度なモックで実態を検証できなくならないようにする。
- 時刻・乱数・外部 API は固定（`travel_to` / stub）して、テストを安定させる。
- 実行は `bin/rails test`（単体）/ `bin/rails test:system`（システム）。

## やらないこと / 確認すること
- 仕様が曖昧なまま大きな変更を進めない。不明点は先に確認する。
- 既存の公開 API・ルーティング・DB スキーマを壊す変更は、影響範囲を説明してから行う。
- 不要な Gem を増やさない。追加する場合はメンテ状況とライセンスを確認し、`Gemfile.lock` の更新も忘れない。
- `config/deploy.rb`・`config/puma.rb`・`.github/workflows/` などインフラ/デプロイ設定の変更は影響が大きいので、内容を説明してから行う。
