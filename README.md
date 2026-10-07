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
| アセット | Sprockets。CSS はフレームワークを使わず手書き（読み込み順は `app/assets/stylesheets/application.css` の冒頭） |
| API | Jbuilder（JSON API） |
| 認証 | Rails 8 標準の認証基盤（has_secure_password + セッション）。`username` + パスワード |
| 外部コマンド | MeCab（読みの自動取得）/ rsvg-convert（og:image の共有カード）。どちらも無くても動く |
| ジョブ | 無し（重い処理は同期で実行する。ActiveJob は雛形のまま） |
| テスト | Minitest / Capybara + Selenium（システムテスト） |
| 静的解析 | rubocop-rails-omakase / Brakeman / bundler-audit / importmap audit |
| CI / CD | GitHub Actions（`ci.yml`: PR の作成時と PR ブランチへの push のたび・main への push 時 / `deploy.yml`: main への push で Capistrano による本番デプロイ。CI の完了は待たない） |
| 周辺 | Cloudflare / Google Analytics 4 |

## コードベースの規模

2026-10-07 時点。行数はコメント・空行を含む物理行（テキストのファイルだけ）。数え直したら日付も直す（数え方は下）。

- Git 管理下のファイル 638 / コード約 42,700 行（`app`・`lib`・`config`・`db`・`test`）
- 2026-06-28 に開発を始め、503 コミット
- テーブル 16 / マイグレーション 29 / テストケース 889 本

| 領域 | ファイル数 | 行数 |
|---|---:|---:|
| `app/models` | 76 | 6,402 |
| `app/controllers` | 41 | 2,036 |
| `app/views` | 156 | 5,342 |
| `app/helpers` | 11 | 1,177 |
| `app/javascript`（Stimulus） | 32 | 2,257 |
| `app/assets/stylesheets` | 8 | 8,107 |
| `lib` | 5 | 246 |
| `config` | 23 | 2,389 |
| `db/migrate` | 29 | 759 |
| `test` | 142 | 11,181 |
| `docs` | 41 | 11,461（うち `docs/refactoring` の作業文書が 22 ファイル・7,253 行） |

```bash
git ls-files | wc -l                                                     # ファイル数
git grep -c '' -- app lib config db test | awk -F: '{s+=$NF} END {print s}' # 行数（領域ごとも同じ形）
git ls-files app/models | wc -l                                         # 領域ごとのファイル数
git rev-list --count HEAD                                               # コミット数
grep -c 'create_table' db/schema.rb                                     # テーブル数
git ls-files db/migrate | wc -l                                         # マイグレーション数
git grep -E '^\s*test "' -- test | wc -l                                # テストケース数
```

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
コマンドの正と、注意点・WSL での実行方法は [`CLAUDE.md`](CLAUDE.md) の「4. 合格判定コマンド（コミット前に必ず実行すること）」にある。

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
| [`docs/history/`](docs/history/README.md) | 記録の置き場（**現行の仕様ではない**） |
| [`docs/history/changelog.md`](docs/history/changelog.md) | これまでに入れたものの記録 |
| [`docs/stats.md`](docs/stats.md) | 統計ページ `/stats` の紙面設計 |
| [`docs/genres.md`](docs/genres.md) | ジャンル階層の一覧 |
| [`docs/char_type_pattern.md`](docs/char_type_pattern.md) / [`docs/rhythm_pattern.md`](docs/rhythm_pattern.md) | 派生値の変換仕様 |
| [`docs/growth-strategy.md`](docs/growth-strategy.md) / [`docs/launch-checklist.md`](docs/launch-checklist.md) | グロース戦略と公開手順 |
| [`docs/history/performance-report.md`](docs/history/performance-report.md) | 速度調査の記録 |
| [`research/README.md`](research/README.md) | Claude Code のオフライン調査コマンドの使い方 |
