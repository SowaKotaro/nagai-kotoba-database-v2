# 長い言葉のデータベース

**読みが 10 文字以上の日本語の言葉**を集め、読みの長さ・リズム・文字種・ジャンルなど
多彩な軸で引けるようにする Web アプリ。

<https://nagai-kotoba-database.jp>

- 単語データの**閲覧は誰でも可能**。**登録・編集・削除は管理者（オーナー）のみ**。
- 収録データは **CC BY 4.0**（クレジット表記 = サイト名 + URL）で公開している。

## 技術スタック

**ビルドツールも外部 CDN も入れない**方針。

| 区分 | 採用技術 |
|---|---|
| 言語 / FW | Ruby 3.4.2 / Rails 8.1 |
| DB | MySQL 8.4（mysql2、utf8mb4。照合順序は `utf8mb4_0900_ai_ci`、読み・表層形のカラムだけ `utf8mb4_0900_as_ci`） |
| アプリサーバ | Puma（本番は systemd で管理） |
| フロントエンド | Hotwire（Turbo・Stimulus）+ importmap-rails |
| アセット | Sprockets。CSS はフレームワークを使わず手書き（`tokens → base → layout → components`） |
| API | Jbuilder（JSON API） |
| 認証 | Rails 8 標準の認証基盤（has_secure_password + セッション）。`username` + パスワード |
| 外部コマンド | MeCab（読みの自動取得）/ rsvg-convert（og:image の共有カード）。どちらも無くても動く |
| ジョブ | ActiveJob（`:async` アダプタ） |
| テスト | Minitest / Capybara + Selenium（システムテスト） |
| 静的解析 | rubocop-rails-omakase / Brakeman / bundler-audit / importmap audit |
| CI / CD | GitHub Actions（`ci.yml`: PR 作成時・main への push 時 / `deploy.yml`: main への push で Capistrano による本番デプロイ） |
| 周辺 | Cloudflare / Google Analytics 4 |

## コードベースの規模

2026-09-27 時点。行数はコメント・空行を含む物理行。

- Git 管理下のファイル 589 / コード約 41,000 行（`app`・`lib`・`config`・`db`・`test`）
- 2026-06-28 に開発を始め、371 コミット
- テーブル 16 / マイグレーション 29 / テストケース 約 809 本

| 領域 | ファイル数 | 行数 |
|---|---:|---:|
| `app/models` | 70 | 5,965 |
| `app/controllers` | 41 | 2,016 |
| `app/views` | 150 | 5,341 |
| `app/helpers` | 12 | 1,157 |
| `app/javascript`（Stimulus） | 31 | 2,219 |
| `app/assets/stylesheets` | 8 | 8,127 |
| `lib` | 5 | 243 |
| `config` | 24 | 2,445 |
| `db/migrate` | 29 | 759 |
| `test` | 134 | 10,177 |
| `docs` | 13 | 3,660 |

## 動かす

ローカルの MariaDB では `utf8mb4_0900_ai_ci` が使えないため、CI・本番と同じ MySQL 8.4 を
Docker で用意して接続する。

```bash
docker compose up -d   # MySQL 8.4（ホスト側ポート 3307）
bin/rails db:prepare   # DB が無ければ作って schema.rb を読み込み、seed を流す（あればマイグレーションだけ）
bin/rails server
```

管理者は `db/seeds.rb` が credentials か環境変数から作る。ローカルで任意の値にするなら:

```bash
ADMIN_USERNAME=xxx ADMIN_PASSWORD=yyy bin/rails db:seed
```

## コミット前のチェック（中身は CI と同じ検査）

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
bin/importmap audit
bin/rails test
bin/rails test:system
```

テストは 2 本に分けて打つ（連結形の `bin/rails test test:system` はローカルでは `LoadError` になる）。
注意点と WSL での実行方法は [`CLAUDE.md`](CLAUDE.md) の「コミット前に必ず実行すること」にある。

## ドキュメント

まず [`docs/overview.md`](docs/overview.md) を読む（全体像・画面一覧・環境変数・ローカル環境）。

| 文書 | 内容 |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | 開発方針・規約（Claude Code 向けだが人が読んでも同じ） |
| [`docs/overview.md`](docs/overview.md) | アプリの全体像（**最初に読む**） |
| [`docs/data-model.md`](docs/data-model.md) | テーブルの関係と設計判断（カラムの正は `db/schema.rb`） |
| [`docs/design.md`](docs/design.md) | デザインシステム「しずか」 |
| [`docs/annotation-guidelines.md`](docs/annotation-guidelines.md) | 収録基準（立項の4原則・表記・読み） |
| [`docs/issues.md`](docs/issues.md) | バックログと、オーナー判断の記録 |
| [`docs/changelog.md`](docs/changelog.md) | これまでに入れたものの記録 |
| [`docs/stats.md`](docs/stats.md) | 統計ページ `/stats` の紙面設計 |
| [`docs/genres.md`](docs/genres.md) | ジャンル階層の一覧 |
| [`docs/char_type_pattern.md`](docs/char_type_pattern.md) / [`docs/rhythm_pattern.md`](docs/rhythm_pattern.md) | 派生値の変換仕様 |
| [`docs/growth-strategy.md`](docs/growth-strategy.md) / [`docs/launch-checklist.md`](docs/launch-checklist.md) | グロース戦略と公開手順 |
| [`docs/performance-report.md`](docs/performance-report.md) | 速度調査の記録 |
| [`research/README.md`](research/README.md) | Claude Code のオフライン調査コマンドの使い方 |
