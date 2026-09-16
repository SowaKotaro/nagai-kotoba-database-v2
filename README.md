# 長い言葉のデータベース

**読みが 10 文字以上の日本語の言葉**を集め、読みの長さ・リズム・文字種・ジャンルなど
多彩な軸で引けるようにする Web アプリ。

<https://nagai-kotoba-database.jp>

- 単語データの**閲覧は誰でも可能**。**登録・編集・削除は管理者（オーナー）のみ**。
- 収録データは **CC BY 4.0**（クレジット表記 = サイト名 + URL）で公開している。

## 技術スタック

Ruby 3.4.2 / Rails 8.1 / MySQL 8（mysql2）/ Puma / Hotwire（Turbo・Stimulus）/
importmap-rails / Sprockets。テストは Minitest、デプロイは Capistrano、CI は GitHub Actions。
**ビルドツールも外部 CDN も入れない**方針。

## 動かす

ローカルの MariaDB では `utf8mb4_0900_ai_ci` が使えないため、CI・本番と同じ MySQL 8.4 を
Docker で用意して接続する。

```bash
docker compose up -d   # MySQL 8.4（ホスト側ポート 3307）
bin/rails db:prepare   # DB 作成 → マイグレーション → seed
bin/rails server
```

管理者は `db/seeds.rb` が credentials か環境変数から作る。ローカルで任意の値にするなら:

```bash
ADMIN_USERNAME=xxx ADMIN_PASSWORD=yyy bin/rails db:seed
```

## コミット前のチェック（CI と同じ）

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
bin/importmap audit
bin/rails test test:system
```

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
