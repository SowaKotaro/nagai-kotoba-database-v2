# プロジェクト方針（nagai-kotoba-database-v2 / Claude Code 向け）

日本語の長い言葉（読み 10 文字以上）を収集・解析・公開する Web アプリ。Rails 8.1 / Ruby 3.4.2 / MySQL 8.4。
この文書が持つのは 4 つだけ: **1. 厳守事項 / 2. 正典パターン（手本つき） / 3. 地図 / 4. 合格判定コマンド**。
アプリの全体像・画面一覧・環境変数・ローカル環境の立ち上げは [`docs/overview.md`](docs/overview.md) にある（新規セッションはまず読む）。
各論の正はリンク先の文書で、ここには写さない。

## 1. 厳守事項

### 書き方と進め方
- 返答・コミットメッセージ・コードコメントは**日本語**で書く。
- 1 Issue = 1 ブランチ = 1 PR（[`docs/issues.md`](docs/issues.md)）。小粒な改善は Issue を立てずに PR だけでよいが、完了の記録は
  [`docs/changelog.md`](docs/changelog.md) の「番号を持たない改善」に 1 行残す。
- ブランチ名は `feature/<内容>`。**Issue / PR 番号は入れない**（Issue と PR で採番が共通なので、付けた番号が必ずずれる）。
- 仕様が曖昧なまま大きな変更を進めない。不明点は先に確かめる。公開 API・ルーティング・DB スキーマを壊す変更は、影響範囲を説明してから行う。
- 変更にはテストを付ける（正常系に加えて異常系・境界値も）。§4 の合格判定が通らないコードは未完成とみなす。エラーは握りつぶさずに直す。

### 公開方針
- 単語データの**閲覧は全世界に公開**、**登録・編集・削除は管理者（オーナー）だけ**。公開側の書き込み経路は
  収録リクエスト（`/requests/new`）だけで、増やさない。
- **公開側にアカウント機能（サインアップ・いいね等）は作らない**。管理者は `username` ＋ パスワードでログインし、
  メール（パスワード再設定）は使わない（仕組みは overview §3）。
- **公開済みの URL とクエリパラメータ名は変えない**（`?sort=created_desc` など。世に出ている）。
- 検索エンジンから見える挙動（robots・canonical・noindex・sitemap）を変えるときは、**URL 空間が無限に広がらないか**を
  確かめる（過去に 2 度クロール事故を起こした。changelog の Issue 80・81）。

### 本番とデプロイ
- **main への merge（push）は、そのまま本番デプロイになる**。deploy.yml が `cap production deploy` を実行し、CI の完了は待たない
  （main にブランチ保護も無い）。merge の前に PR 上の CI が通ったことを確かめる。関門は PR 上の CI と `/cppmtm` の手順だけ。
- デプロイでは `deploy:migrate` の直後に `deploy:seed` が毎回走る（`SeedCatalog` の `*_RENAMES` に書いた改名も、このとき本番に効く）。
  本番 DB の接続情報はサーバ上の `config/database.yml` が持つ（overview §8）。
- `config/deploy.rb`・`config/puma.rb`・`.github/workflows/` などインフラとデプロイの設定は、内容を説明してから変える。

### セキュリティ
- **Strong Parameters** で許可した属性だけを受け付ける（書き方は §2）。
- **SQL は必ずプレースホルダ**を使い、文字列展開でクエリを組まない。
  NG: `Word.where("surface = '#{params[:q]}'")` / OK: `Word.where(surface: params[:q])`・`Word.where("surface = ?", params[:q])`
- **認可**: 認証は全アクションで既定で必須。公開側は開放するアクションを明示し、書き込み経路を漏らさない（§2）。
- ビューの出力はエスケープに任せる。`html_safe` / `raw` / `<%==` を安易に使わない。
- 機密情報をコードに直書きしない（`Rails.application.credentials` か環境変数）。`config/master.key` はコミットしない。
  ログに個人情報・パスワード・トークンを出さない（`config.filter_parameters`）。
- 公開面から叩ける重い処理（重複チェックの総当たりなど）には、レートリミットかキャッシュのどちらかを必ず付ける。

### DB
- スキーマの正は `db/schema.rb`。直接編集せず、マイグレーションで変える。**適用済みのマイグレーションは書き換えない**。
  マイグレーションはロールバックできるように書く（`change` で書けなければ `up` / `down`）。
- **照合順序**: 全テーブル `utf8mb4_0900_ai_ci`。ただし**読み・表層形のカラムは `utf8mb4_0900_as_ci`**（ai は清濁を同一視して
  「ハ=バ=パ」になる）。**読み・表層形を持つカラムを新設するときは `as_ci` を明示する**。何を同一視するかと対象カラムの一覧は data-model §6。
- 大きなテーブルへの変更（カラム追加・インデックス・ロック）は、本番への影響を一言添える。

### 依存と構成
- 不要な gem・JS ライブラリを足さない（足すならメンテ状況とライセンスを確かめ、`Gemfile.lock` も更新する）。
- ビルドツール（webpack 等）・CSS フレームワーク・web フォント・外部 CDN を入れない。Hotwire（Turbo / Stimulus）＋ importmap ＋
  手書き CSS（Sprockets）のまま、JS は最小限にする。

### UI（見た目を作る・変えるとき）
- **UI を作る・変える、または雰囲気を確かめるときは、必ず [`docs/design.md`](docs/design.md) を読む**（デザインシステム「しずか」
  ＝読むための、しずかな場所。値と規約の正）。過去のデザインは失効しており、「以前そう決めた」を根拠に差し戻さない。
  **退けた案は design.md §12 にまとめてあり、再提案しない**。
- 装飾を足す方向に倒さない（新しい要素を 1 つ足すなら、既にあるものを 1 つ削る）。
- 色はトークンだけで、アクセントカラーを持たない（赤／緑は「エラー／達成」のときだけ。多色は統計 §1 のワードクラウドだけ。管理画面だけ 2 色）。
- 太字を使わない（`font-weight` 400、`b` / `strong` だけ 500）。書体は `--font-sans`・`--font-mono`・`--font-display` の 3 つだけ。
- 区画は面の色＋1px の罫＋余白で示し、影を使わない。並んだ要素どうしの罫は `border` ではなく `gap: 1px` の隙間で作る。
- 動きはホーム最上部の印だけ。図版は実データから描く線画 2 種だけ（写真の枠を置かない）。
- 淡さの下限（文字は白地 4.5:1、面と罫は白との差 ΔRGB 19）を割らない。**色を薄くしたら必ず実測する**。
- 管理画面は「しずか」を引き継がない。HTML は公開側と共有し、`body.is-admin` の下で `admin.css` が上書きする（design.md §10）。

## 2. 正典パターン（新しく書くときは手本に倣う）

### 置き場所と設計
- **Ruby のクラスは `app/models` に置く**（ActiveRecord と、値オブジェクト・クエリ／集計・書き込み処理・フォーム・調査 JSON の入出力）。
  **`app/services` は外部プロセスを起動するラッパーだけ**（手本 `share_card_renderer.rb`）。`concerns` は複数のクラスが include する振る舞い。
  サブディレクトリは作らない（定数名が変わる）。
- クラスの冒頭に `# 種別:` を書く。`app/models` は `値オブジェクト（DB に触れない）`・`クエリ・集計（読み取りとキャッシュ）`・`書き込み処理`・`フォーム`・
  `調査 JSON の入出力` の 5 つ（ActiveRecord には書かない）、`app/services` は `外部コマンドのラッパー`。
- コントローラはリクエストの受け渡しに徹し、規則はモデルへ（Fat Controller / Fat Model を避ける）。既存の Rails / gem で済むものを自作しない。
  名前は意図が伝わるように付け、省略しすぎない。重複は適度にまとめるが、過度な抽象化より読みやすさを取る。
- **同じ規則を 2 つの画面が名乗るなら、定義は 1 か所**（手本 `Admin::AnnotationQueue`、`WordSense::KEYWORD_MATCH_CONDITION`、
  登録予定単語の段 `WordCandidate::STAGES`）。片方だけ変わると、同じ名前の画面で違う結果が出る。
- **基準値・しきい値は概念の持ち主に 1 つだけ置き、別名の定数を作らない**（`WordSense::MIN_READING_LENGTH`、`Levenshtein::SIMILARITY_THRESHOLD`、
  立項スコアと確信度は `AnnotationProposal`、マスタ名は `SeedCatalog`）。マジックナンバーは定数に、状態は間隔を空けた整数の enum にする（手本 `word_candidate.rb`）。
- 公開条件は、語は `Word.annotated`、語義は `WordSense.published` だけを使う。公開側のクエリはここから始めるか、ここで選んだ id だけを受け取る
  （スコープを通らない公開出力は data-model §8）。
  代表語義は `Word#primary_sense`、かなの畳み込みは `KanaFold`、絶対 URL は `SiteUrl`、並び順は `WordSort` の定数（新着順も `"created_desc"`）。

### 派生値と DB
- **派生値は手入力させない**。作る場所は SQL の STORED 生成カラム（`t.virtual ..., stored: true`）／値オブジェクト＋`before_validation`／
  `after_commit` で焼き直す代表値（`WordSenseMetrics`）の 3 つ。どの列をどこで作り、何に依存し、どう直すかの正は data-model §3。
- 値オブジェクトは `self.call(input)` の純粋関数にする（手本 `last_char.rb`）。変換が複数あるものは名前付きのクラスメソッド（`KanaFold.to_katakana`）。
  語義の読み由来の値は `WordSense.reading_derivations` の 1 か所で作る。
- 派生列を足したら、data-model §3 の表・backfill・verify を同じコミットで直す。コールバックを通らない更新（`update_all`・`update_columns`・生 SQL）には
  理由をその場でコメントする。読み・表層形をそれで書き換えたら、`bin/rails backfill:verify` で見つけて `backfill:reading_metrics` で直す（data-model §3.4）。
- 検証はモデルと DB 制約の両方で持つ（`NOT NULL`・unique index ＋ `validates`）。外部キー・検索条件・一意制約のカラムにはインデックスを張り、
  長い文字列は prefix index（`surface(191)`）。複数レコードの整合が要る更新は `transaction` でまとめる。
- マスタ名は `SeedCatalog` が唯一の正。コードで名前を使うときはカタログの定数を参照し、テストで固定する（手本 `test/models/linguistic_feature_glossary_test.rb`）。
  用語は「言語学的特徴」に揃える。
- アプリのスイッチ（環境変数）は `config/application.rb` で 1 回だけ読み、`config.x` に置く（手本 `REQUESTS_ENABLED`）。
- rake タスクは規則をモデルに任せ、冪等にし、desc に触る列をすべて書く。トップレベルで `def` しない。

### コントローラ・ヘルパ・ビュー
- **認証**: `ApplicationController` が全アクションを認証必須にしている。公開側は `allow_unauthenticated_access only: %i[...]` で
  開放するアクションを明示する（手本 `words_controller.rb`）。管理側は `Admin::BaseController` を継承するだけでよい。
- **Strong Parameters**: モデルに渡す属性は `params.require(:x).permit(...)`（手本 `admin/word_candidates_controller.rb`）。
  複数の画面で共有する許可の集合は定数 1 つにする（`Admin::AnnotationQueue::WORD_ATTRIBUTES`）。
- **動的な SQL 片**（並び替え・集計）は定数の文字列リテラルで書き切る（手本 `WordSort`・`WordSenseMetrics`。外部入力が混ざらないことを静的解析でも追える）。
- **N+1 を作らない**。関連を辿るループの前に `includes` / `preload` を使う（word → word_senses → 各マスタは特に）。
- **キャッシュ**: 集計値は集計クラスのクラスメソッドで持ち、版付きの `CACHE_KEY`・`CACHE_TTL`・`RACE_CONDITION_TTL` を付ける（手本 `published_sense_counts.rb`。
  無効化は TTL だけ）。既知の例外: race_condition_ttl を持たないのは `WordRanking`・`HomeStatistics`・`AboutStatistics`、キーに版が無いのは
  `WordRequestDuplicateCheck`。全件出力（sitemap・llms-full）の本文だけはコントローラでキャッシュし、版と TTL は `PublishedWordsDigest` のものを使う。
  ほかのコントローラには HTTP の宣言（`expires_in` / `stale?`）だけを書く。
- 図や表の「印」（最頻のビン・最多の行・比率）と、件数の合算は、集計クラスかコントローラが決めて渡す。ビューでは数えない。
- ヘルパは値・属性・文字列を返し、マークアップのまとまりはパーシャルにする。ヘルパで DB を引くならメモ化する。
  JS に渡す値と文言はヘルパで data ハッシュを組む（手本 `WordRequestsHelper#reading_counter_data`）。
- 新しいパーシャルは冒頭で `<%# locals: (name:, extra_class: nil) -%>` を宣言し、中でインスタンス変数と `params` を読まない。2 画面以上で使う部品はパーシャル 1 つにする。
- 表示文言は `config/locales/ja.yml` に置き `t(...)` で引く（ハードコードしない）。新しいキーはビューのパスに合わせ、区切り記号も i18n に置く。
  列挙値は生の値ではなく i18n のラベルで出す。フラッシュはレイアウトの `#flash` だけに出す。

### 重い処理・外部連携・調査 JSON
- ジョブは 1 本も無い（`app/jobs` は雛形だけ）。重い処理（共有カードの描画・代表値の UPDATE・MeCab の読み取得）は同期で実行し、
  共有カードはタイムアウト・Mutex・ファイルキャッシュで守っている（`ShareCardRenderer`）。メール・外部 API・重い集計を足すときは非同期を相談する
  （ジョブ基盤の第一候補は Solid Queue。ジョブは冪等に作る）。`before_save` などのコールバックに外部通信や重い副作用を詰め込まない。
- **外部コマンド**（`mecab`・`rsvg-convert`）は、無くても機能が止まらない形にする（読みは空欄で手入力、og:image は既定カード）。
  手本 `share_card_renderer.rb`: 有無の判定はクラスで 1 回、コマンドは配列で渡す、タイムアウトを持つ、`SystemCallError` を捕まえる、
  失敗は nil を返して呼び出し側が既定値へ倒す。外部 API を呼ぶならタイムアウトと例外処理を必ず入れる。
- **調査 JSON**: 取り込みの手本は `word_candidate_notation_import.rb`（`ResearchJson.array_at` で読み、読めなければ nil、行ごとに `requires_new`、
  結果は `Struct`）。書き出しの手本は `annotation_research_export.rb`（`VERSION` を付ける）。提案 JSON のキーの正は `AnnotationProposal` の定数。
- **調査スキル**（`.claude/skills/`・`.claude/commands/`）は RuboCop とテストの外にある。スキルからはアプリの公開メソッドだけを呼び、規則は写さずに
  正典の節を参照する。スキルの文書を直したら、claude.ai 用のスキル束を作り直す（`tools/claude-ai-skill/build.sh`。アップロードはオーナー）。

### JavaScript（Stimulus）
- 1 コントローラ 1 目的。冒頭コメントに、目的・使う画面・JS が無いとどうなるか・連携するイベントを書く（手本 `decision_list_controller.js`）。
- Ruby の値と文言は data 属性で受け、日本語や基準値を直書きしない（文言のプレースホルダは `%{name}`）。
- ページ全体のイベントは data-action の `@window` / `@document` で受ける（手本 `shared/_header.html.erb` の nav-menu）。`addEventListener` は
  matchMedia などに限り、disconnect で外す。コントローラ同士は `this.dispatch()` と受け手の data-action で結ぶ（document 全体に流すのは `theme:change` だけ）。
- 開閉する部品は Turbo がキャッシュする前に閉じ（手本 `nav_menu_controller.js`）、タイマーは disconnect で止める。
- DOM はサーバのマークアップを `<template>` target から複製して作る（手本 `nested_form_controller.js`）。fetch は `inline_add_controller.js` の `post()`
  の形にし、失敗は必ず画面に出す。複数のコントローラが使う関数は `controllers/support/` に置く。
- 要素を探す手がかりは Stimulus の target か data 属性にする（`js-` 接頭辞のクラスは増やさない）。localStorage は try/catch で包む（手本 `theme_controller.js`）。
  段階的な強化は、サーバが全部を描き、JS が畳む形にする（`data-js-only`）。

### CSS
- 色は `var(--token)` だけ。トークンを足すときは tokens.css にライトの値・`--dark-*`・2 つの適用ブロックを書く（直書きしてよい範囲は tokens.css の冒頭）。
- 部品の手本: `.tag`・`.btn`・`.form-alert`・`.visually-hidden`・`.check-chip`。並んだ要素の罫は `.entry-list` の `gap: 1px`。
  複数の部品が揃えて持つ値はトークンにする（`--frame-width`）。CSS と Ruby が同じ値を持つときは、ビューから CSS 変数で渡す（手本 `KanaRing.stroke_length`）。
- 管理画面の上書きは admin.css の `.is-admin` に集める（`.is-admin *` の全称セレクタで `transition` を潰さない。かえって重くなる）。
- 幅の切り替えは広い幅を基底にし、狭い幅を `max-width` で上書きする（ブレークポイントは design.md §7、クラス名の付け方は design.md §11）。

### テスト（Minitest）
- **1 つの振る舞いは 1 つの層で検証する**: 変換・判定の規則はモデルと値オブジェクト、画面の出し分け・リンク・フォームの項目名は結合テスト
  （`assert_select`）。system テストは実ブラウザ（JS の実行・レイアウトの計算）が要る挙動だけに書き、同じ画面の操作は 1 回の `visit` にまとめる。
  同じ前提で分けただけの結合テストも 1 本にまとめ、重いページ（`/stats` など）の GET を重ねない。
- 管理画面のテストは `setup { sign_in_as(admins(:one)) }` でログインする（手本 `test/controllers/admin/candidates/lists_controller_test.rb`）。
  未ログインの拒否は `test/integration/admin_authentication_test.rb` が全ルートについて検証するので、各テストには書かない。
- データはフィクスチャが基本。公開語は `create_published_word` で作り（手本 `test/controllers/words_controller_test.rb`）、`create!` に派生値を渡さない。
  外部に出る形式はキーの集合ごと固定する（手本 `test/integration/words_api_test.rb`）。canonical ホストは test_helper の `CANONICAL_HOST`。
- 時刻・乱数・外部 API は固定する（`travel_to` / stub）。キャッシュを通して確かめるときは、ビューの `cache` は `with_fragment_cache`、
  `Rails.cache.fetch` は `with_rails_cache`。設定と ENV は `with_config` / `with_env`（いずれも test_helper）。過度なモックで実態を隠さない。
- 外部コマンドに依存するテストは `available?` を見て skip し、フォールバックは `available?` を false にして確かめる（手本 `test/services/share_card_renderer_test.rb`）。
- system テストの操作ヘルパ（`wait_for_stimulus`・`click_expecting`・`click_via_js`・`click_accepting_confirm` など）の使い分けは、
  `test/application_system_test_case.rb` の注記が正。
- 役目を終えたテスト（もう無いマークアップの不在の確認、ルートヘルパや関連の宣言そのものの確認）は残さない。

### 文書とコメント
- 事実ごとに正を 1 か所に置き、ほかからはリンクする（カラムは `db/schema.rb`、派生値は data-model §3、照合順序は data-model §6、
  デザインは design.md、環境変数は overview §8、調査の流れは `research/README.md`、ルートは `config/routes.rb`）。
- コメントに残すのは、なぜ・不変条件・外部との約束・長いファイルの区画見出し。直後のコードの言い換えは書かない。
- 参照は行番号ではなく、シンボル名と「文書名＋節」で書く。件数は書かずに出どころを指す。数値を書くなら式か出どころを添える。
- design.md・stats.md の節番号は変えない（コードのコメントが節番号で指している）。足すなら末尾か小節、移すなら欠番にして行き先を 1 行残す。

## 3. 地図

| 場所 | 役割 | 手本・入口 |
|---|---|---|
| `app/models/` | ActiveRecord と、ほかの Ruby のクラスすべて（冒頭に種別） | 値オブジェクト `char_type_pattern.rb`、集計 `published_sense_counts.rb`、取り込み `word_candidate_notation_import.rb` |
| `app/models/concerns/` | 複数のモデルが include する振る舞い | `refreshes_word_metrics.rb`（代表値の焼き直し）・`tag_master.rb` |
| `app/services/` | 外部コマンドのラッパー（`reading_extractor` と `morpheme_extractor` は MeCab、`share_card_renderer` は rsvg-convert） | `share_card_renderer.rb` |
| `app/controllers/` | 公開側（`words/` は共有カード）と `admin/`（`Admin::BaseController` を継承） | `words_controller.rb`・`admin/word_candidates_controller.rb` |
| `app/controllers/concerns/` | 認証 `Authentication`、全件出力の版 `PublishedWordsDigest`、注釈のキュー `Admin::AnnotationQueue` | — |
| `app/helpers/` | ビューに渡す値・属性・data ハッシュ | `word_requests_helper.rb` |
| `app/views/` | ERB。公開側の共通部品は `shared/`、管理画面の共通部品は `admin/shared/` | `shared/_genre_path` |
| `app/javascript/controllers/` | Stimulus（importmap）。共有の関数は `support/`。Plotly は意図してピンせず、Sprockets で配信する | `decision_list_controller.js` |
| `app/assets/stylesheets/` | 手書き CSS。tokens → base → layout → components → annotate・candidates・admin の順に読み、**管理用の CSS も全ページで読む** | `tokens.css` |
| `config/locales/ja.yml` | 表示文言 | — |
| `config/routes.rb` | ルートの正（画面の役割は overview §5） | — |
| `config/linguistic_features_glossary.yml` | 言語学的特徴の用語解説（seed のマスタ名と 1 : 1） | — |
| `db/schema.rb`・`db/migrate/` | スキーマの正と、その変更 | `20260924100000_create_word_candidates.rb`（as_ci の明示） |
| `db/seeds.rb` | 管理者とマスタを冪等に投入する（名前の正は `SeedCatalog`） | — |
| `db/morpheme_frequencies.json` | 統計 §1 のワードクラウドの事前集計（ローカルの `bin/rails stats:morphemes` で作ってコミットする） | — |
| `lib/tasks/` | backfill（派生値の再生成と検証）・stats（形態素頻度）・dev_samples（開発用のダミー） | `backfill.rake` |
| `test/` | models・controllers・integration・system・services・helpers・tasks・assets。共通のヘルパは `test_helper.rb` と `test_helpers/`（`sign_in_as`） | `test_helper.rb`・`application_system_test_case.rb` |
| `.claude/skills/`・`.claude/commands/`・`research/` | 調査スキル（ローカルの Claude Code）と、その入出力 | `research/README.md` |
| `script/og_default.py`・`tools/claude-ai-skill/build.sh` | 既定の共有カード `public/og-default.png` の生成、claude.ai 用のスキル束の生成 | — |
| `docs/` | 仕様と記録（索引は overview の冒頭） | — |

## 4. 合格判定コマンド（コミット前に必ず実行すること）

コードを変えたら、コミット前に次をすべて通し、**指摘をすべて解消する**。中身は CI（`.github/workflows/ci.yml`）と同じ検査。

```bash
bundle exec rubocop                      # スタイル / 静的解析（rubocop-rails-omakase）
bundle exec brakeman --no-pager          # セキュリティ静的スキャン
bundle exec bundler-audit check --update # gem 依存の既知脆弱性
bin/importmap audit                      # JS 依存の既知脆弱性
bin/rails test                           # テスト（単体・結合）
bin/rails test:system                    # テスト（システム。Chrome が要る）
```

- テストは 2 本に分けて打つ。連結形の `bin/rails test test:system` は、ローカルでは `LoadError` になる（`test:system` をファイルのパスとして読むため）。
  CI の `bin/rails db:test:prepare test test:system` は、先頭が rake タスクなので全体が rake タスクとして解釈されて通る。
- ローカルで通っても CI で落ちることがある。test 環境の eager load は環境変数 `CI` があるときだけ効く（`config/environments/test.rb`）ので、
  CI と同じ条件で試すには `CI=1` を付ける。
- テストの DB は Docker の MySQL 8.4（`docker compose up -d`。overview §7）。
- WSL では、システムテストに Chrome のパスを渡す: `CHROME_BIN=<Selenium Manager が選ぶ chromedriver と同じメジャー版の Chrome> bin/rails test:system`。
  Chrome の依存ライブラリが足りない環境では、`LD_LIBRARY_PATH` も要る。
- RuboCop は安全な範囲で `bundle exec rubocop -a` の自動修正を使ってよい。機械で検出できる項目（スタイル・既知の脆弱性）はこれらに任せ、
  この文書は機械では測りにくい設計・命名の観点を受け持つ。
