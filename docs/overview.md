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
| これまでに入れたもの | [`changelog.md`](changelog.md) |
| 統計ページの紙面 | [`stats.md`](stats.md) |
| 速度の話 | [`performance-report.md`](performance-report.md) |
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
- CSS は手書き（`tokens → base → layout → components` ＋ `admin.css` / `annotate.css`）
- テスト: **Minitest**（`test/` 配下。RSpec は使っていない）
- デプロイ: **Capistrano**（`cap production deploy`。`deploy:migrate` の後に `deploy:seed` が自動実行）
- CI: GitHub Actions（PR 作成時・main への push 時。DB は `mysql:8.4`）
- タイムゾーンは `Tokyo`、既定ロケールは `:ja`（表示文言は `config/locales/ja.yml` に集約）
- 外部サービスへの実行時依存は持たない（web フォント CDN・チャート CDN・外部 API いずれも無し。
  唯一の同梱ライブラリが `vendor/javascript/plotly.min.js` で、統計ページ内でのみ遅延読み込みする）

## 3. 認証（管理者）

- Rails 8 標準の認証基盤（`has_secure_password` ＋ セッション）。モデルは `Admin`。
- ログインは **`username`（ID）＋ パスワード**。**メールは使わない**（パスワード再設定機能も持たない）。
- **サインアップ画面は無い**。管理者は `db/seeds.rb` が credentials か環境変数
  （`ADMIN_USERNAME` / `ADMIN_PASSWORD`）から冪等に作成／更新する。
- セッションは 2 週間のスライディング失効（`Session::LIFETIME`）。
- `Admin::BaseController` 配下は既定で認証必須。公開閲覧は名前空間の外に置き、
  `allow_unauthenticated_access` で明示的に開放する。

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
| `/admin/candidates` | **登録予定単語**。一覧（ステータスで絞り込み → 語を選んで処理）と upload。前処理の各段は `/admin/candidates/expand`・`/duplicate`・`/notation` |

- 管理画面は**「しずか」を引き継がない**。HTML は公開側と共有したまま、`body.is-admin` の下で
  トークンだけ上書きする（[`design.md`](design.md) §10）。
- 単語の編集画面は無い。表層形の訂正も含めてアノテーション・コンソールに統合済み。

## 6. コードの地図

```
app/models/          ActiveRecord ＋ 値オブジェクト ＋ フォーム/クエリオブジェクト
  ├ 本体            word / word_sense / word_sense_feature / word_sense_origin / word_sense_variant
  ├ マスタ          genre / entity_type / part_of_speech / linguistic_feature / word_origin
  ├ 認証            admin / session / current
  ├ 値オブジェクト  char_type_pattern / rhythm_pattern / vowel_pattern / mora_count / last_char /
  │                 levenshtein / search_regexp / kana_ring / kana_row / radial_chart / word_sort /
  │                 word_ranking / share_card_typesetter / word_share_card
  ├ クエリ/集計      word_sense_search / site_statistics / published_sense_counts / word_sense_metrics /
  │                 related_words / shiritori_words / morpheme_cloud / morpheme_frequencies
  ├ アノテーション   annotation_proposal / annotation_proposal_import / proposal_application /
  │                 annotation_masters / annotation_deck_form / annotation_deck_save /
  │                 bulk_annotation / bulk_proposal_approval / proposed_master_creation /
  │                 annotation_research_export / feature_research_export / reannotation_export
  ├ リクエスト      word_request / word_request_item / word_request_duplicate_check / word_request_form_token
  ├ 登録予定単語    word_candidate / word_candidate_intake / word_candidate_duplicate_check /
  │                 word_candidate_export / word_candidate_expansion_import / word_candidate_notation_import
  └ その他          research_json（調査 JSON の貼り付けを読む）/ seed_catalog（マスタ seed の単一の正）/ tag_kind / linguistic_feature_glossary
app/services/        reading_extractor（MeCab CLI）/ morpheme_extractor / share_card_renderer（rsvg-convert）
app/controllers/     公開（words / searches / browse / genres / rankings / stats / pages / llms /
                     sitemaps / robots / word_requests / home）＋ admin/ 名前空間
app/javascript/      Stimulus のみ（importmap）。1 コントローラ 1 目的
app/assets/          手書き CSS（tokens → base → layout → components ＋ admin / annotate）
db/schema.rb         スキーマの正（マイグレーション経由で更新）
db/seeds.rb          管理者とマスタを冪等に投入（名前リストは SeedCatalog が単一の正）
db/morpheme_frequencies.json  統計 §1 ワードクラウドの事前集計結果（コミットするデータファイル）
config/locales/ja.yml 表示文言（ハードコードしない）
config/linguistic_features_glossary.yml  言語学的特徴の用語解説（seed のマスタ名と 1 : 1）
lib/tasks/           backfill（派生値の再生成・検証）/ stats（形態素頻度）/ dev_samples（開発用ダミー）
script/og_default.py 既定の共有カード public/og-default.png の生成
tools/claude-ai-skill/build.sh  claude.ai 用の /reannotation スキル束を生成
```

## 7. ローカル開発環境

ローカルの MariaDB では `utf8mb4_0900_ai_ci` が使えないため、**CI・本番と同じ MySQL 8.4 を
Docker で用意**して接続する。

```bash
docker compose up -d   # MySQL 8.4 を起動（ホスト側 3307。既存 3306 との衝突を避けるため）
bin/rails db:prepare   # DB 作成 → マイグレーション → seed
bin/rails server
```

- development / test は既定で `127.0.0.1:3307`（`DATABASE_HOST` / `DATABASE_PORT` で上書き可）。
  production は socket ＋ 環境変数。
- 管理者をローカルで任意の値にする: `ADMIN_USERNAME=xxx ADMIN_PASSWORD=yyy bin/rails db:seed`
- デザイン確認用のダミーデータ: `bin/rails dev:sample_data`（開発環境専用・冪等）
- **開発環境はキャッシュが既定で無効**（`:null_store`）。`/stats`・`/rankings`・`/llms-full.txt`
  が「本番より遅い」ときはまずこれを疑う。`bin/rails dev:cache` で本番相当に切り替わる。

### 任意の外部コマンド（無くても機能は止まらない）

| コマンド | 使う場所 | 無いとどうなるか |
|---|---|---|
| `mecab`（＋ mecab-ipadic-neologd） | 一括登録 step2 の読み自動取得（`ReadingExtractor`） | 読みが空欄になり、確認画面で手入力する |
| `mecab`（既定辞書 ipadic） | 統計 §1 の形態素頻度の事前集計（`bin/rails stats:morphemes`） | 集計を更新できない（本番は JSON を読むだけなので影響なし） |
| `rsvg-convert` ＋ 日本語の書体 | 単語ごとの共有カード（`ShareCardRenderer`） | og:image が既定カード `og-default.png` のままになる |

- 読みの取得は **neologd**、形態素の分解は**既定辞書**を使う。neologd は「涼宮ハルヒの憂鬱」を
  丸ごと 1 語で持つので、部品を数える用途では逆効果になる（目的が逆なので辞書の選択も逆）。
- 辞書の場所は `MECAB_DICT` で上書きできる。無ければ既定辞書へフォールバックする。
- これらに依存するテストは、コマンドが無い環境では skip する（CI もこの扱い）。
- **本番サーバには rsvg-convert と Noto CJK を導入済み**（2026-09-15）。入れ直したら Puma を
  再起動する（有無の判定はプロセスごとに 1 回だけ行うため）。
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
| `NAGAI_KOTOBA_DATABASE_V2_PASSWORD` | — | リポジトリの `database.yml` と `deploy.rb` が参照するが、**本番では使われていない**（下記） |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | credentials | `db:seed` が作る管理者。環境変数が優先 |
| `RAILS_MASTER_KEY` | `config/master.key` | credentials の復号鍵 |
| `WEB_CONCURRENCY` | `1` | Puma のワーカー数。**増やすとキャッシュと `rate_limit` が worker 間で分裂する**（`:memory_store` のため） |
| `SURFACES_FILE` | 未設定 | `bin/rails stats:morphemes` に本番相当の入力（1 行 1 語）を渡す |

本番はこれらを Puma の systemd unit（override.conf）に置いている。

> **本番 DB の接続情報は環境変数ではない。** `config/database.yml` は Capistrano の `linked_files`
> に入っているので、本番で読まれるのは**サーバ上の共有ファイル**で、そこにパスワードが直書きされている。
> リポジトリ側の `production:` ブロックと `deploy.rb` の `default_env` は実質使われていない
> （2026-09-16 に確認。[`issues.md`](issues.md) 確定事項 28）。

## 9. コミット前の必須チェック（CI と同一）

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
bin/importmap audit
bin/rails test test:system
```

これが通らないコードは「未完成」とみなす。システムテストは WSL では Chrome の版まわりで
不安定になりやすいので、実行方法は `CLAUDE.md` とセッションのメモを参照する。

## 10. 進め方の規約

- **1 Issue = 1 ブランチ = 1 PR** を原則とする（[`issues.md`](issues.md)）。
  小粒な改善は Issue を立てずに PR だけで進めてよい（その場合も完了記録は `issues.md` に残す）。
- ブランチ名は `feature/<内容>`。**Issue / PR 番号は入れない**（Issue と PR で採番カウンタが
  共通なので、付けた番号が必ずずれる）。
- 返答・コミットメッセージ・コードコメントは**日本語**。
