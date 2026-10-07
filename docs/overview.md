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
- デプロイ: **Capistrano**（`cap production deploy`）。**main への push（PR の merge を含む）で
  `.github/workflows/deploy.yml` が自動で実行する**。CI の完了は待たず、main にブランチ保護も無い。
  `deploy:migrate` の直後に `deploy:seed` が毎回走り、管理者とマスタ（`SeedCatalog` の `*_RENAMES` による改名を含む）を投入する
- CI: GitHub Actions（`.github/workflows/ci.yml`。PR の作成時と PR ブランチへの push のたび、main への push 時。DB は `mysql:8.4`）。
  main への push ではデプロイと並走するので、CI が落ちてもデプロイは止まらない
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
| `/search` | 詳細検索フォーム（13 条件）。実行すると条件付きの `/words` へ |
| `/browse` | 50 音・読みの文字数の索引 |
| `/genres` | ジャンル階層のハブ |
| `/rankings` | 各種ランキング（読みの長さ・モーラ数・円環交差数など 11 種） |
| `/stats` | 収録統計。数字の壁 ＋ 8 章。紙面の正は [`stats.md`](stats.md) |
| `/requests/new` | 収録リクエスト（公開側で唯一の書き込み経路。`REQUESTS_ENABLED` で停止できる） |
| `/about` `/privacy` | サイト情報・プライバシーポリシー |
| `/words.json` `/words/:id.json` | 公開 JSON API（CC BY 4.0 表記つき） |
| `/words.atom` | 新着単語の Atom フィード（注釈済み新着 20 件） |
| `/llms.txt` `/llms-full.txt` | LLM 向けのサイト案内と、全収録データの全文版 |
| `/sitemap.xml` `/robots.txt` | どちらも動的生成。`Sitemap:` 行は canonical ホストに連動 |
| `/up` | ヘルスチェック（Rails 標準） |

公開側はダークモードに対応（OS 設定追従 ＋ ヘッダーのトグル）。
アカウント機能（サインアップ・いいね等）は**今後も作らない**。

### 管理側（`/admin` 配下・認証必須）

| パス | 内容 |
|---|---|
| `/admin` | ダッシュボード。収録状況と各画面への入口 |
| `/admin/words` | 一覧（検索・注釈状態/タグの絞り込み・一括適用・削除） |
| `/admin/words/new` | **一括登録（3ステップ）**: 入力（箇条書き）→ 読み → 重複チェック → 登録 |
| `/admin/annotations` | **アノテーション・コンソール**（1 語集中キュー。保存して次へ） |
| `/admin/annotation_deck` | **アノテーション・デッキ**（既定 10 件をまとめて開き、1 回の送信で保存） |
| `/admin/annotation_proposals` | Claude Code 連携。調査用データの書き出し／提案 JSON の取り込み |
| `/admin/bulk_proposal_approval` | 厳格ゲートを満たす提案の一括承認（プレビュー → 承認・公開） |
| `/admin/tags` | **タグ統括管理**。5 種のマスタの一覧・リネーム・削除・統合 |
| `/admin/requests` | 公開側から届いた収録リクエストの確認・一括処理 |
| `/admin/candidates` | **登録予定単語**。入口は仕分け（貼り付けて追加し、語ごとに 拡張 / 採用 / 保留 / 除外 を選んで一度に確定）。前処理の各段は `/admin/candidates/expand`（拡張）・`/notation`（表記と、その確認）・`/ready`（登録待ち → 一括登録へ）、状態で絞り込む一覧は `/all` |

- 管理画面は**「しずか」を引き継がない**。HTML は公開側と共有したまま、`body.is-admin` の下で
  トークンだけ上書きする（[`design.md`](design.md) §10）。
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
  production は socket ＋ 環境変数。
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

| 変数 | 既定 | 効果 |
|---|---|---|
| `INDEXING_ENABLED` | 未設定 | **未設定 = 全ページ noindex**。設定すると通常ページの robots メタが消える（解禁スイッチ） |
| `REQUESTS_ENABLED` | `true` | `false` で収録リクエストの受付を止め、導線ごと隠す |
| `CANONICAL_HOST` | `https://nagai-kotoba-database.jp` | canonical / OGP / sitemap の絶対 URL の基点（末尾スラッシュ無し） |
| `GA4_MEASUREMENT_ID` | 未設定 | 設定すると GA4 の gtag を出力する（Turbo 対応の page_view 送信） |
| `GOOGLE_SITE_VERIFICATION` / `BING_SITE_VERIFICATION` | 未設定 | 所有権確認の meta タグ（DNS 確認が使えないとき用） |
| `MECAB_DICT` | 未設定 | MeCab の辞書パス。未設定なら neologd の既定パス → 既定辞書の順にフォールバック |
| `DATABASE_HOST` / `DATABASE_PORT` | `127.0.0.1` / `3307` | development / test の接続先（CI は 3306） |
| `NAGAI_KOTOBA_DATABASE_V2_PASSWORD` | — | リポジトリの `database.yml` と `deploy.rb` が参照し、deploy.yml も GitHub の secret から渡すが、**本番では使われていない**（下記） |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | credentials | `db:seed` が作る管理者。環境変数が優先 |
| `RAILS_MASTER_KEY` | `config/master.key` | credentials の復号鍵 |
| `WEB_CONCURRENCY` | `1` | Puma のワーカー数。**増やすとキャッシュと `rate_limit` が worker 間で分裂する**（`:memory_store` のため） |
| `SURFACES_FILE` | 未設定 | `bin/rails stats:morphemes` に本番相当の入力（1 行 1 語）を渡す |

本番はこれらを Puma の systemd unit（override.conf）に置いている。

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
