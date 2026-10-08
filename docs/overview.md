# アプリ概要（最初に読むドキュメント）

新しく参加する開発者（および Claude Code セッション）が全体像を掴むための案内。
方針・規約は [`CLAUDE.md`](../CLAUDE.md) が正。各論はリンク先の文書が正。

| 知りたいこと | 読む文書 |
|---|---|
| 守る規約・やってよいこと/いけないこと | [`CLAUDE.md`](../CLAUDE.md) |
| テーブルの関係と設計判断 | [`data-model.md`](data-model.md)（カラムの正は `db/schema.rb`） |
| UI を作る・変える | [`design.md`](design.md) |
| 何を収録するか・表記と読みの決め方 | [`annotation-guidelines.md`](annotation-guidelines.md) |
| これから作るもの | [`issues.md`](issues.md)（確定事項の記録も同じファイル） |
| これまでに入れたもの | [`history/changelog.md`](history/changelog.md) |
| 記録の置き場（済んだこと・当時の計測。**現行の仕様ではない**） | [`history/`](history/README.md) |
| 統計ページの紙面 | [`stats.md`](stats.md) |
| 速度の話 | [`history/performance-report.md`](history/performance-report.md) |
| ジャンルの一覧 | [`genres.md`](genres.md) |
| Claude Code の調査コマンド | [`../research/README.md`](../research/README.md) |

---

## 1. コンセプト

- **日本語の長い言葉を収集・解析・公開する Web アプリ**（<https://nagai-kotoba-database.jp>）。
- 収録対象は **読みが 10 文字以上**の語。判定基準は [`annotation-guidelines.md`](annotation-guidelines.md)。
- 語ごとに 読み・意味・ジャンル・品詞・エンティティ・語種・言語学的特徴・別表記 を構造化して蓄積し、
  **読みの長さ・モーラ数・先頭/末尾文字・文字種パターン・リズム（ローマ字）・母音パターン・ジャンル階層**
  といった多彩な軸で検索・絞り込みできるようにする。
- ポジションは「読みの長さ・リズム・文字種で引ける、長い言葉に特化したデータベース」
  （総合辞書と正面から戦わない。[`growth-strategy.md`](growth-strategy.md) §0）。
- **公開方針**: 単語データの**閲覧は全世界に公開**。**登録・編集・削除は管理者（オーナー）のみ**。
  公開側で唯一の書き込み経路は収録リクエスト（`/requests/new`）。
- 想定規模: 1 万レコード程度。

## 2. 技術スタック

- **Ruby 3.4.2 / Rails 8.1**（`config.load_defaults 8.1`）
- **MySQL 8.x（mysql2）** — 照合順序は `utf8mb4_0900_ai_ci` 基準（読みまわりだけ `as_ci`。[`data-model.md`](data-model.md) §6）
- Puma / Hotwire（Turbo・Stimulus）/ importmap-rails / Sprockets — **ビルドツールは入れない**
- CSS は手書き（`tokens → base → layout → components` ＋ `annotate.css` / `candidates.css` / `admin.css`）
- テスト: **Minitest**（`test/` 配下。RSpec は使っていない）
- デプロイ: **Capistrano**（`cap production deploy`）。**main への push（PR の merge を含む）で自動で実行する**（§11）
- CI: GitHub Actions（`.github/workflows/ci.yml`。DB は `mysql:8.4`。§11）
- タイムゾーンは `Tokyo`、既定ロケールは `:ja`（表示文言は `config/locales/ja.yml` に集約）
- 外部サービスへの実行時依存は持たない（web フォント CDN・チャート CDN・外部 API いずれも無し。
  唯一の同梱ライブラリが `vendor/javascript/plotly.min.js` で、統計ページ内でのみ遅延読み込みする）

## 3. 認証（管理者）

- Rails 8 標準の認証基盤（`has_secure_password` ＋ セッション）。モデルは `Admin`。
- ログインは **`username`（ID）＋ パスワード**。**メールは使わない**（パスワード再設定機能も持たない）。
- **サインアップ画面は無い**。管理者は `db/seeds.rb` が credentials か環境変数
  （`ADMIN_USERNAME` / `ADMIN_PASSWORD`）から冪等に作成／更新する。
- セッションは 2 週間のスライディング失効（`Session::LIFETIME`）。
- 認証は**全アクションで既定で必須**（`ApplicationController` が `Authentication` を include している）。
  `Admin::BaseController` 配下はそれを継承するだけで管理者専用になる。公開閲覧は名前空間の外に置き、
  `allow_unauthenticated_access only: %i[...]` で明示的に開放する。

## 4. データモデル（要点）

詳細は [`data-model.md`](data-model.md)。カラム定義の正は `db/schema.rb`。

- `words` : `word_senses` = **1 : 多**（同音異義語に対応）。
- `genres` は**隣接リスト**（`parent_id`）で 大 → 中 → 小 の3階層。`word_senses.genre_id` は
  **末端（小分類）のみ**を指し、中・大は親を辿って一意に導出する。
- `linguistic_features` は `word_sense_features` 経由で語義と多対多。**単語の該当部分ごと**に付ける
  （`target` / `target_reading` / `target_start`）。
- `word_origins`（語種）も多対多（混種語に対応）。`word_sense_variants` は別表記。
- 読み・表層形からの派生値は**すべて自動生成**する（SQL の STORED 生成カラム／Ruby の値オブジェクト／
  `after_commit` での代表値の焼き直しの3通り）。
- **公開されるのは `words.annotated_at` が立っている語だけ**。この日時が「収録日」として
  公開面の日付・並び順にも使われる（`created_at` は使わない）。

## 5. 画面の一覧

### 公開側（誰でも閲覧可）

| パス | 内容 |
|---|---|
| `/` | ホーム。サイト名の読みの円環 → 看板（検索）→ 今日の一語 → 新着 / 読みが長い |
| `/words` | 単語一覧。絞り込み（ファセット）・並び替え・シャッフル・ページネーション |
| `/words/:id` | 単語詳細。語義・関連データ・五十音円環・関連語・しりとりの次の一手 |
| `/words/random` | ランダムに 1 語へ 302 |
| `/words/:id/share_card.png` | 単語ごとの共有カード（og:image） |
| `/search` | 詳細検索フォーム（条件の並びは `searches/index.html.erb`、受け付けるパラメータは `WordSenseSearch#to_query_params`）。実行すると条件付きの `/words` へ |
| `/browse` | 50 音・読みの文字数の索引 |
| `/genres` | ジャンル階層のハブ |
| `/rankings` | 各種ランキング（読みの長さ・モーラ数・円環交差数など。種類は `WordRanking::DEFINITIONS`） |
| `/stats` | 収録統計。数字の壁と各章（紙面の正は [`stats.md`](stats.md)） |
| `/requests/new` | 収録リクエスト（公開側で唯一の書き込み経路。`REQUESTS_ENABLED` で停止できる） |
| `/about` `/privacy` | サイト情報・プライバシーポリシー |
| `/words.json` `/words/:id.json` | 公開 JSON API（CC BY 4.0 表記つき） |
| `/words.atom` | 新着単語の Atom フィード（注釈済みの新着。件数は `WordsController::FEED_LIMIT`） |
| `/llms.txt` `/llms-full.txt` | LLM 向けのサイト案内と、全収録データの全文版 |
| `/sitemap.xml` `/robots.txt` | どちらも動的生成。`Sitemap:` 行は canonical ホストに連動 |
| `/up` | ヘルスチェック（Rails 標準） |

公開側はダークモードに対応（OS 設定追従 ＋ ヘッダーのトグル）。
アカウント機能（サインアップ・いいね等）は**今後も作らない**。

### 管理側（`/admin` 配下・認証必須）

| パス | 内容 |
|---|---|
| `/session/new` | 管理者のログイン（`username` ＋ パスワード。§3） |
| `/admin` | ダッシュボード。収録状況と各画面への入口 |
| `/admin/words` | 一覧（検索・注釈状態/タグの絞り込み・一括適用・削除） |
| `/admin/words/new` | **一括登録（3ステップ）**: 入力（箇条書き）→ 読み → 重複チェック → 登録 |
| `/admin/annotations` | **アノテーション・コンソール**（1 語集中キュー。保存して次へ）。1 語の再調査用の書き出しは `/admin/annotations/:id/reresearch` |
| `/admin/annotation_deck` | **アノテーション・デッキ**（複数語をまとめて開き、1 回の送信で保存。既定の語数は `Admin::AnnotationDecksController::DEFAULT_SIZE`） |
| `/admin/annotation_proposals/export`・`/export_features`・`/new` | Claude Code 連携。調査用データの書き出し（語・言語学的特徴）と、提案 JSON の取り込み |
| `/admin/bulk_proposal_approval` | 厳格ゲートを満たす提案の一括承認（プレビュー → 承認・公開） |
| `/admin/tags` | **タグ統括管理**。マスタ（種別は `TagKind::MODELS`）の一覧・リネーム・削除・統合 |
| `/admin/requests` | 公開側から届いた収録リクエストの確認・一括処理 |
| `/admin/candidates` | **登録予定単語**。入口は仕分け（貼り付けて追加し、語ごとに 拡張 / 採用 / 保留 / 除外 を選んで一度に確定）。前処理の各段は `/admin/candidates/expand`（拡張）・`/notation`（表記と、その確認）・`/ready`（登録待ち → 一括登録へ）、状態で絞り込む一覧は `/all`、1 語の表示と手直しは `/admin/candidates/:id` |

- 管理画面は**「しずか」を引き継がない**。HTML は公開側と共有したまま、`body.is-admin` の下で
  トークンと一部のコンポーネントの見た目を上書きする（[`design.md`](design.md) §10）。
- 単語の編集画面は無い。表層形の訂正も含めてアノテーション・コンソールに統合済み。

## 6. コードの地図

[`CLAUDE.md`](../CLAUDE.md) の「3. 地図」へ移した（ディレクトリ → 役割 → 手本。全ファイルの列挙は古くなるので持たない）。
ActiveRecord 以外のクラスは、ファイルの冒頭の「種別:」の行に種別を書いてある。

## 7. ローカル開発環境

ローカルの MariaDB では `utf8mb4_0900_ai_ci` が使えないため、**CI・本番と同じ MySQL 8.4 を
Docker で用意**して接続する。

```bash
docker compose up -d   # MySQL 8.4 を起動（ホスト側 3307。既存 3306 との衝突を避けるため）
bin/rails db:prepare   # DB が無ければ作って schema.rb を読み込み、seed を流す（あればマイグレーションだけ）
bin/rails server
```

- 新しい環境は `db:prepare`（schema.rb の読み込み）で作る。マイグレーションを最初から流し直す `db:migrate` は、
  CI でも流しておらず、通ることは保証しない（古いマイグレーションはアプリのコードを呼んでいる）。
- development / test は既定で `127.0.0.1:3307`（`DATABASE_HOST` / `DATABASE_PORT` で上書き可）。
  production の接続情報はサーバ上の `config/database.yml` で、リポジトリの production ブロックは使われていない（§8 の注記）。
- 管理者をローカルで任意の値にする: `ADMIN_USERNAME=xxx ADMIN_PASSWORD=yyy bin/rails db:seed`
- デザイン確認用のダミーデータ: `bin/rails dev:sample_data`（開発環境専用・冪等）
- **開発環境はキャッシュが既定で無効**（`:null_store`）。`/stats`・`/rankings`・`/llms-full.txt`
  が「本番より遅い」ときはまずこれを疑う。`bin/rails dev:cache` で本番相当に切り替わる。

### 任意の外部コマンド（無くても機能は止まらない）

| コマンド | 使う場所 | 無いとどうなるか | 本番・CI |
|---|---|---|---|
| `mecab`（＋ mecab-ipadic-neologd） | 一括登録 step2 の読み自動取得（`ReadingExtractor`） | 読みが空欄になり、確認画面で手入力する | どちらにも無い（本番の step2 は読みが空欄で出る） |
| `mecab`（既定辞書 ipadic） | 統計 §1 の形態素頻度の事前集計（`bin/rails stats:morphemes`） | 集計を更新できない（本番は JSON を読むだけなので影響なし） | どちらにも無い（集計はローカルで行い、`db/morpheme_frequencies.json` をコミットする） |
| `rsvg-convert` ＋ 日本語の書体 | 単語ごとの共有カード（`ShareCardRenderer`） | og:image が既定カード `og-default.png` のままになる | 本番は導入済み（下記）。CI には無い |

- 読みの取得は **neologd**、形態素の分解は**既定辞書**を使う。neologd は「涼宮ハルヒの憂鬱」を
  丸ごと 1 語で持つので、部品を数える用途では逆効果になる（目的が逆なので辞書の選択も逆）。
- 読みの取得（`ReadingExtractor`）の辞書の場所は `MECAB_DICT` で上書きできる。無ければ既定辞書へ
  フォールバックする。形態素の分解（`MorphemeExtractor`）は `MECAB_DICT` を見ず、いつも既定辞書を使う。
- これらに依存するテストは、コマンドが無い環境では skip する（CI もこの扱い）。skip の判定は、
  各サービスのクラスメソッド `available?` を見る。
- **有無の判定は、3 つのサービスともプロセスごとに 1 回だけ行う**（クラスの `available?` がメモする）。
  コマンドを入れたり外したりしたら、Puma（rake なら次の実行）を起動し直すまで反映されない。
- **本番サーバには rsvg-convert と Noto CJK を導入済み**（2026-09-15）。入れ直したら Puma を
  再起動する。
- sudo の無い環境で本番と同じ描画を試すには、パッケージを展開して使う:

  ```bash
  apt-get download librsvg2-bin fonts-noto-cjk
  dpkg-deb -x librsvg2-bin_*.deb rsvg && dpkg-deb -x fonts-noto-cjk_*.deb fonts
  # fonts.conf: <fontconfig><dir>(展開先)/fonts/usr/share/fonts/opentype/noto</dir>
  #             <include ignore_missing="yes">/etc/fonts/fonts.conf</include></fontconfig>
  PATH="$PWD/rsvg/usr/bin:$PATH" FONTCONFIG_FILE="$PWD/fonts.conf" bin/rails server
  ```

## 8. 環境変数

種類: **アプリ** = このアプリ（設定・seed・rake・サービス）が読む変数（画面の振る舞いを変えるスイッチは `config/application.rb` で 1 回だけ読み、`config.x` に置く）／
**Rails・Puma** = フレームワークの標準／**テスト** = テストと開発のときだけ／**Actions** = GitHub Actions のシークレット（アプリは読まない）。

| 変数 | 種類 | 既定 | 効果 |
|---|---|---|---|
| `INDEXING_ENABLED` | アプリ | 未設定 | **未設定 = 全ページ noindex**。設定すると通常ページの robots メタが消える（解禁スイッチ）。**値は見ず、空でなければ解禁**になる（`false` を入れても解禁） |
| `REQUESTS_ENABLED` | アプリ | `true` | `false` で収録リクエストの受付を止め、導線ごと隠す（真偽値として読む） |
| `CANONICAL_HOST` | アプリ | `https://nagai-kotoba-database.jp` | canonical / OGP / sitemap の絶対 URL の基点（末尾スラッシュ無し。`SiteUrl`） |
| `GA4_MEASUREMENT_ID` | アプリ | 未設定 | 設定すると GA4 の gtag を出力する（Turbo 対応の page_view 送信） |
| `GOOGLE_SITE_VERIFICATION` / `BING_SITE_VERIFICATION` | アプリ | 未設定 | 所有権確認の meta タグ（DNS 確認が使えないとき用） |
| `MECAB_DICT` | アプリ | 未設定 | MeCab の辞書パス（`ReadingExtractor` が読む）。未設定なら neologd の既定パス → 既定辞書の順にフォールバック |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | アプリ | credentials | `db:seed` が作る管理者。環境変数が優先 |
| `SURFACES_FILE` | アプリ | 未設定 | `bin/rails stats:morphemes` に本番相当の入力（1 行 1 語）を渡す |
| `RAILS_MASTER_KEY` | Rails・Puma | `config/master.key` | credentials の復号鍵 |
| `RAILS_ENV` | Rails・Puma | `development` | 動かす環境 |
| `RAILS_LOG_LEVEL` | Rails・Puma | `info` | production のログの段階 |
| `WEB_CONCURRENCY` | Rails・Puma | `1` | Puma のワーカー数。**増やすとキャッシュと `rate_limit` が worker 間で分裂する**（`:memory_store` のため） |
| `RAILS_MAX_THREADS` / `RAILS_MIN_THREADS` | Rails・Puma | `5` / 最大と同じ | Puma のスレッド数。DB のコネクションプールも最大と同じ数にする（`config/database.yml`） |
| `PORT` / `PIDFILE` | Rails・Puma | `3000` / `tmp/pids/server.pid` | Puma の待ち受けとプロセス ID のファイル |
| `REDIS_URL` | Rails・Puma | 未設定 | `config/cable.yml` の production の雛形の値。Action Cable を購読する画面が無いので、読まれない |
| `DATABASE_HOST` / `DATABASE_PORT` | テスト | `127.0.0.1` / `3307` | development / test の接続先（CI は 3306） |
| `CI` | テスト | 未設定 | 設定すると test 環境でも eager load する（CI と同じ条件で試す。[`CLAUDE.md`](../CLAUDE.md) §4） |
| `CHROME_BIN` | テスト | 未設定 | システムテストで使う Chrome（WSL で、chromedriver と同じメジャー版を指す。[`CLAUDE.md`](../CLAUDE.md) §4） |
| `SSH_PRIVATE_KEY` / `KNOWN_HOSTS` | Actions | — | deploy.yml が本番サーバへ SSH で入るための鍵と known_hosts |
| `NAGAI_KOTOBA_DATABASE_V2_PASSWORD` | Actions | — | リポジトリの `database.yml` と `deploy.rb` が参照し、deploy.yml も渡すが、**本番では使われていない**（下記） |

本番の環境変数は Puma の systemd unit（override.conf）に置いている（テストと Actions の行を除く）。

> **本番 DB の接続情報は環境変数ではない。** `config/database.yml` は Capistrano の `linked_files`
> に入っているので、本番で読まれるのは**サーバ上の共有ファイル**で、そこにパスワードが直書きされている。
> リポジトリ側の `production:` ブロック、`deploy.rb` の `default_env`、deploy.yml が渡す secret は実質使われていない
> （2026-09-16 に確認。[`issues.md`](issues.md) 確定事項 28）。

## 9. コミット前の必須チェック（中身は CI と同じ検査）

コマンドの正は `CLAUDE.md` の「4. 合格判定コマンド（コミット前に必ず実行すること）」にある（6 本。テストは `bin/rails test` と
`bin/rails test:system` の 2 本に分けて打つ。連結形の `bin/rails test test:system` はローカルでは `LoadError` になる）。
これが通らないコードは「未完成」とみなす。WSL でのシステムテストの実行方法（`CHROME_BIN` など）も `CLAUDE.md` にある。

## 10. 進め方の規約

[`CLAUDE.md`](../CLAUDE.md) の「1. 厳守事項」の「書き方と進め方」へ移した（1 Issue = 1 ブランチ = 1 PR、ブランチ名、日本語で書くこと）。

## 11. 運用

既存の節番号を変えないよう、末尾に足した節（2026-10-07）。デプロイ・CI・定期実行・派生物の作り直しの正はここ。

- **デプロイ**: main への push（PR の merge を含む）で `.github/workflows/deploy.yml` が `cap production deploy` を実行する。
  **CI の完了は待たず、main にブランチ保護も無い**（merge の前に PR 上の CI を確かめる。[`CLAUDE.md`](../CLAUDE.md) の厳守事項）。
  - `deploy:migrate` の直後に `deploy:seed` が毎回走り、管理者とマスタを冪等に投入する（`SeedCatalog` の `*_RENAMES` に書いた改名もこのとき適用される）。
  - 本番の DB 接続はサーバ上の `config/database.yml`（`linked_files`）、環境変数は Puma の systemd unit（§8）。
  - deploy.yml が使うシークレットは §8 の「Actions」の行。
- **CI**: `.github/workflows/ci.yml`。PR の作成時と PR ブランチへの push のたび、main への push 時に走る。
  main への push ではデプロイと並走するので、**CI が落ちてもデプロイは止まらない**。中身は [`CLAUDE.md`](../CLAUDE.md) §4 の合格判定と同じ。
  失敗した system テストのスクリーンショットは、成果物 `screenshots` に残る（`gh run download <run> -n screenshots`）。
- **定期実行**: 候補語を集める `/harvest` を、オーナーのローカルの crontab がヘッドレスの Claude Code で 1 日 2 回動かしている
  （時刻とセットは [`research/README.md`](../research/README.md) の「使う順番」）。**cron の定義はリポジトリの外にある**ので、
  スキルが新しい権限（Bash など）を要るように変わると、黙って失敗する。ログは `research/harvest-cron.log`（git の外）。
- **claude.ai 用のスキル束**: `/reannotation` を claude.ai で使うための束は、`tools/claude-ai-skill/build.sh` が作る派生物。
  元は、再注釈と注釈のスキルの SKILL.md・[`annotation-guidelines.md`](annotation-guidelines.md)・`config/linguistic_features_glossary.yml`・
  注釈スキルの `schema.json` と `example.json`。**どれかを直したら、束を作り直してアップロードし直す**（アップロードはオーナー）。
- **本番の確かめ方**: ヘルスチェックは `/up`。派生値の整合は、サーバで `RAILS_ENV=production bin/rails backfill:verify`
  （[`data-model.md`](data-model.md) §3.4）。インデックスの状況は Search Console を週次で見る（[`launch-checklist.md`](launch-checklist.md) §4）。

## 12. JS の地図

既存の節番号を変えないよう、末尾に足した節（2026-10-07）。ここは索引で、書き方の正典は [`CLAUDE.md`](../CLAUDE.md) の
「JavaScript（Stimulus）」、各コントローラの目的・JS が無いときの振る舞い・連携するイベントは、そのファイルの冒頭のコメントにある。

### コントローラ（`app/javascript/controllers/`。画面ごと）

| 画面 | コントローラ |
|---|---|
| 共通（ヘッダー） | `nav_menu`（「検索」のプルダウン）・`nav_drawer`（狭幅のドロワー）・`theme`（ダークモード） |
| 単語の一覧・詳細 | `auto_submit`（並び替えを選んだら送る。管理の一覧でも使う）・`clipboard`（URL のコピー。管理画面の書き出しでも使う） |
| 詳細検索 | `genre_filter`（ジャンルの絞り込み）・`range_slider`（読みの文字数）・`char_type`・`char_type_toggle`（文字種） |
| ランキング・統計 | `panel_switch`（セグメントボタンでパネルを切り替える）・`genre_sunburst`（Plotly）・`vowel_graph`（母音のつながり） |
| 収録リクエスト | `nested_form`（行の追加と削除）・`reading_counter`（読みの字数） |
| アノテーション（コンソール・デッキ） | `nested_form`・`sense_cloner`（語義の複製）・`sense_completeness`（必須項目の充足）・`genre_picker`（ジャンルの段階表示）・`inline_add`（マスタのその場追加）・`feature_range`（特徴の該当部分）・`publish_guard`（公開前の確認）・`queue_nav`（キーボード）・`deck`（カード送り） |
| 管理の一覧・一括登録 | `check_all`（全選択）・`genre_picker`（一括適用）・`reading_choice`（読みの候補）・`reading_format`（読みの形式） |
| 登録予定単語 | `decision_list`（語ごとの処理）・`row_select`（行の選択）・`submit_shortcut`（Ctrl+Enter で送る） |

複数のコントローラが使う関数は `controllers/support/`（いまは `senses.js` と `create_master.js`）。stimulus-loading は `_controller` で終わるファイルしか
登録しないので、ここに置いた関数はコントローラにならない。マスタのその場追加の fetch は `support/create_master.js` の `createMaster()` を使う（`inline_add` と `genre_picker`）。

### 独自のイベント

コントローラ同士は `this.dispatch()` で出し、受け手は data-action（`<出す側>:<名前>->受け手#メソッド`）で受ける。document 全体に流すのは `theme:change` だけ。

| イベント | 出す側 | 受ける側 |
|---|---|---|
| `theme:change`（document） | `theme` | `genre_sunburst`（Plotly の色を CSS のトークンから読み直す） |
| `char-type-toggle:changed` | `char_type_toggle` | `char_type#caseSensitivityChanged` |
| `genre-picker:changed` | `genre_picker` | `sense_completeness#check` |
| `inline-add:added` | `inline_add` | `sense_completeness#check` |
| `sense-completeness:changed` | `sense_completeness` | `deck#recount` |
| `decision-list:applied`・`decision-list:filtered` | `decision_list` | `row_select#clear` |

Turbo のイベントでは、`turbo:before-cache`（`nav_menu` がキャッシュ前に閉じ、`clipboard` が完了の表示を元の文言に戻す）と `turbo:frame-render`（`decision_list` が行の手直しから戻ったときにフォーカスを戻す）を受けている。

### DOM の約束事

- **段階的な強化**: サーバが全部を描き、JS がつながってから畳む・見せる。`data-js-only` は JS が無いと働かない部品で、
  `row_select` が接続するまで CSS が隠す（`candidates.css`）。`panel_switch` の `hideOnConnect` は、全パネルを描いておき、つながってから畳む。
- `data-row-group` は「この系統を選ぶ」でまとめて選ぶ行の範囲（`row_select`）。
- 行の `data-decision`・`data-flags`、処理のラジオの `data-key`、絞り込みのボタンの `data-flag` は `decision_list` が読み書きする。
- `data-nested-form-item`・`data-nested-form-destroy`・`data-sense-destroy` は、`nested_form`・`sense_cloner` が行と削除の印を探す手がかり。
- `html[data-theme]` は `theme` が付け外しする（初回の描画の前の復元だけは head のインラインスクリプト。[`design.md`](design.md) §9.2）。

### フックの名前の付け方

- JS から要素を探す手がかりを新しく足すときは、Stimulus の target か data 属性にする。`js-` 接頭辞のクラスは既存の注釈コンソールにだけ残し、
  増やさない（`js-` が付いていても、JS が使うとは限らない）。
- 見た目用のクラスを JS やテストも参照している箇所は、CSS の側に「JS（〜_controller.js）・テストも参照」と注記する（[`design.md`](design.md) §11）。
- Plotly は importmap にピンせず、Sprockets で配信して UMD のグローバルとして使う（`config/importmap.rb` の注記。`bin/importmap audit` の対象外）。

## 13. 事実ごとの正（単一の出典）

既存の節番号を変えないよう、末尾に足した節（2026-10-07）。同じ事実をほかの文書に書くときは、写さずにここで指す正へリンクする。

| 事実 | 正 |
|---|---|
| 守る規約・正典パターン・合格判定コマンド | [`CLAUDE.md`](../CLAUDE.md) |
| カラム定義 | `db/schema.rb` |
| テーブルの関係と設計判断 | [`data-model.md`](data-model.md) |
| 派生値（作る場所・作り直し・verify） | [`data-model.md`](data-model.md) §3 |
| 照合順序（何を同一視するか・as_ci の列・Ruby 側で頼っている所） | [`data-model.md`](data-model.md) §6 |
| 整合性（DB 制約とモデルの検証） | [`data-model.md`](data-model.md) §7 |
| 公開の境目と、公開スコープを通らない公開出力 | [`data-model.md`](data-model.md) §8 |
| デザインの値・規約・退けた案 | [`design.md`](design.md)（ΔRGB の式は §1、ブレークポイントは §7、退けた案は §12） |
| CSS の読み込み順と置き場所 | `app/assets/stylesheets/application.css` の冒頭 |
| 統計の図の規則（色の段・操作・データの出どころ） | [`stats.md`](stats.md) |
| ルート | `config/routes.rb`（画面の役割は §5） |
| 環境変数 | §8 |
| デプロイ・CI・定期実行・派生物の作り直し | §11 |
| JS のコントローラ・イベント・DOM の約束事 | §12（中身の正は各ファイルの冒頭コメント） |
| 調査の流れ（スキル → 管理画面） | [`research/README.md`](../research/README.md) |
| 提案 JSON のキー | `AnnotationProposal` の定数（`SENSE_KEYS`・`META_KEYS`・`PAYLOAD_KEYS`）。schema.json と各 SKILL.md はその写し |
| 書き出す調査 JSON の形 | 各書き出しクラス（`AnnotationResearchExport`・`FeatureResearchExport`・`ReannotationExport`）の `as_json` |
| マスタ名（大分類・中分類・品詞・語種・言語学的特徴） | `SeedCatalog`（[`genres.md`](genres.md) はその写し） |
| マスタ名（小分類・エンティティ種別） | DB（調査用の書き出しの `masters` が現況） |
| 言語学的特徴の定義 | `config/linguistic_features_glossary.yml`（注釈スキルの対応表はその写し） |
| 収録基準 | [`annotation-guidelines.md`](annotation-guidelines.md) §0 と `WordSense::MIN_READING_LENGTH` |
| 立項スコア・表記の決め方・読みの表記・確信度 | [`annotation-guidelines.md`](annotation-guidelines.md) §2・§3・§4・§8 |
| 語種・ジャンル・エンティティ・特徴の付け方、意味の文体 | 注釈スキル（`.claude/skills/word-annotation-research/SKILL.md`） |
| 登録予定単語の段 | `WordCandidate::STAGES` |
| オーナーの判断 | [`issues.md`](issues.md) の確定事項（失効したものは [`history/decisions.md`](history/decisions.md)） |
| 済んだことの記録 | [`history/`](history/README.md)（[`history/changelog.md`](history/changelog.md) ほか） |
