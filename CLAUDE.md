# プロジェクト方針（nagai-kotoba-database-v2 / Claude Code 向け）

> **最初に読む**: アプリの全体像・画面一覧・環境変数・ローカル環境の立ち上げは
> [`docs/overview.md`](docs/overview.md) にまとまっている。新規セッションはまずこれを参照する。

## 言語・コミュニケーション
- 返答・コミットメッセージ・コードコメントは原則 **日本語** で記述する。

## このプロジェクトについて
- アプリ概要: **日本語の長い言葉（読み 10 文字以上）を収集・解析・公開する Web アプリ**。
- 公開方針: **単語データの閲覧は全世界に公開**（誰でも閲覧可）。**登録・編集・削除は管理者（オーナー）のみ**。
  公開側で唯一の書き込み経路は収録リクエスト（`/requests/new`）。
- **公開側にアカウント機能（サインアップ／いいね等）は作らない**。
- 認証: 管理者認証は **Rails 8 標準の認証基盤**（has_secure_password + セッション）。モデルは `Admin`、
  ログインは **`username`(ID) + パスワード**（メールは使わない）。サインアップ画面は無く、管理者は
  `db/seeds.rb`（credentials / 環境変数）で作成する。**パスワード再設定（メール）機能は持たない**。
- バージョン: **Ruby 3.4.2 / Rails 8.1**
- 構成: Rails + **MySQL（mysql2）** + Puma + Hotwire（Turbo / Stimulus）+ importmap-rails + Sprockets
- テスト: **Minitest**（`test/` 配下。RSpec は使っていない）
- デプロイ: **Capistrano**（`cap production deploy`）。デプロイ後に `deploy:seed` が自動実行される。
  本番 DB の接続情報は**サーバ上の `config/database.yml`**（`linked_files` の共有ファイル）が持つ。
  リポジトリの `database.yml` と `deploy.rb` の `default_env` は本番では使われていない。
- CI: GitHub Actions（`.github/workflows/ci.yml`）。**PR 作成時** と **main への push 時** に実行。

## データモデル（詳細は [`docs/data-model.md`](docs/data-model.md)。カラムの正は `db/schema.rb`）
- `word` : `word_sense` = **1 : 多**（同音異義語に対応）。
- `genres` は **隣接リスト**（`parent_id`）で 大→中→小の3階層。`word_senses.genre_id` は末端（小分類）を指す。
- `linguistic_features` は `word_sense_features` 経由で語義と**多対多**。特徴は単語の**該当部分ごと**に
  付ける（`target` / `target_reading` / `target_start`）。`word_origins`（語種）も多対多（混種語対応）。
- **派生値は必ず自動生成する**（手入力させない）。作る場所は3通り:
  - **SQL の STORED 生成カラム**: `word_senses.reading_length` / `first_char`、
    `words.surface_length` / `reading_density`
  - **Ruby の値オブジェクト ＋ `before_validation`**: `char_type_pattern`（漢/あ/ア/1/A/a/@）・
    `rhythm_pattern`（ヘボン式ローマ字）・`vowel_pattern`・`mora_count`・`ring_crossing_count`・`last_char`
  - **`after_commit` で焼き直す代表値**: `words` の `min_*` / `max_*` / `sense_count` /
    `variant_count` / `feature_count`（並び替え・ランキングの指標。`WordSenseMetrics`）
  - `last_char` は本来 SQL の生成カラムにしたいが、生成式にマルチバイト文字を含めると
    ActiveRecord の SchemaDumper（mysql2 アダプタ）が `schema.rb` をダンプする際に文字化けする
    既知の制限があるため、例外的に Ruby 側で計算する（`app/models/last_char.rb`）。
  - `update_all` や生 SQL で `reading` / `surface` を書き換えたら、`bin/rails backfill:verify` で
    差分を検出し `backfill:reading_metrics` / `backfill:sense_metrics` で直す。
- **照合順序**: 日本語検索が中心のため全テーブルを **`utf8mb4_0900_ai_ci`** に統一する方針。
  長い文字列カラムは prefix index（例 `surface(191)`）を使う。ただし **読み・表層形まわりは
  例外的に `utf8mb4_0900_as_ci`**（ai は濁点・半濁点を同一視して「ハ=バ=パ」になるため。as_ci なら
  清濁を区別しつつ、ひらがな⇔カタカナ・A⇔a の同一視は保てる）。
  対象は `words.surface` / `words.max_reading` / `min_reading` / `min_reversed_reading` /
  `word_senses.reading` / `first_char` / `last_char` / `word_sense_variants.surface` / `reading` /
  `word_request_items.surface` / `reading`。**読み・表層形を持つカラムを新設するときは `as_ci` を明示する。**

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
  - 動的に組む必要がある SQL 片（並び替え・集計）は**定数の文字列リテラルで書き切る**
    （`WordSort` / `WordSenseMetrics` の方針。外部入力が混ざらないことを静的解析でも追えるようにする）。
- **認可を徹底する**。閲覧（read）は全世界に公開だが、**登録・編集・削除は管理者のみ**。
  - 書き込み系アクションには認証必須の `before_action` を必ず付ける（管理者未ログインは弾く）。
  - 公開閲覧アクションは `allow_unauthenticated_access` で明示的に開放し、書き込み経路を漏らさない。
- ビュー出力は基本エスケープに任せる。`html_safe` / `raw` / `<%==` は安易に使わない。
- 機密情報をコードに直書きしない。`Rails.application.credentials`（`config/credentials.yml.enc`）か環境変数を使う。`config/master.key` はコミットしない。
- ログに個人情報・パスワード・トークンを出さない（`config.filter_parameters` を設定）。
- 公開面から叩ける重い処理（重複チェックの総当たりなど）には、レートリミットかキャッシュの
  どちらかを必ず付ける。

## ActiveRecord / データベース
- **N+1 を作らない**。関連を辿るループの前に `includes` / `preload` / `eager_load` を使う（word→word_senses→各マスタは特に注意）。
- 外部キー・検索条件・ユニーク制約のカラムには **インデックス**を張る。
- バリデーションは **モデルと DB 制約の両方**で担保する（`NOT NULL` / `unique index` ＋ モデルの `validates`）。
- 複数レコードの整合性が必要な更新は `transaction` でまとめる。
- マイグレーションはロールバック可能に書く。`change` で表現できない処理は `up` / `down` を定義する。
- スキーマは `db/schema.rb` が正。直接編集せずマイグレーション経由で更新する。
- MySQL（utf8mb4）前提。文字数・絵文字・照合順序に注意する。STORED 生成カラムは `t.virtual ..., stored: true` で定義する。
- 大きなテーブルへの変更（カラム追加・インデックス・ロック）は本番への影響を一言添える。

## 設計・アーキテクチャ
- **Fat Controller / Fat Model を避ける**。コントローラはリクエストの受け渡しに徹する。
- ビジネスロジック（`char_type_pattern`・`rhythm_pattern` の生成など）が膨らんだら Service Object / Value Object / Concern に切り出す（`app/models/concerns`・`app/controllers/concerns` を活用）。
- `before_save` などのコールバックに、外部 API 通信や重い副作用を詰め込まない。
- 既存の Rails / Gem の機能で済むものを自作しない。**Rails の規約（CoC）に沿う**。
- フロントは Hotwire（Turbo / Stimulus）+ importmap 構成。ビルドツール（webpack 等）は導入しない方針。JS は最小限に。
- **同じ規則を2画面が名乗るなら、定義は1箇所に置く**（例: アノテーションのキューは
  `Admin::AnnotationQueue`、キーワード検索の一致条件は `WordSense::KEYWORD_MATCH_CONDITION`）。
  片方だけ変わると、同じ名前の画面で違う結果が出る。

## デザイン / UI（見た目を作る・変えるとき）
- **UI を作る/変更する、または雰囲気・トーンを確認するときは、必ず [`docs/design.md`](docs/design.md) を読む**。
  本プロジェクトのデザインシステム「**しずか（Shizuka）**＝読むための、しずかな場所」の確定仕様。
  下は「これだけは破らない」要点で、**値と経緯の正は design.md**。
- **手本は「しずかなインターネット」（<https://sizu.me>）**。配色・級数・角丸・余白は実サイトから採寸した値を使っている。
  **長時間の滞在と再訪で疲れないこと**が最優先で、**情報は疎でよい**。
  手本は役割で分けている: 静けさ・余白・文字組み = sizu.me ／ 標識と図としての数字 = ただ、そこ ／
  線画 = mud Inc. ／ 全幅の帯 = TOFT。
- **色**: アクセントカラーを持たない（白 × 無彩色グレー ＋ ごく淡い青みの面）。赤／緑は
  「エラー／達成」の意味を持つときだけ。チャートの塗りだけ `--chart`。
  **多色はサイト唯一の例外として統計 §1 のワードクラウドだけ**（`--cloud-1`〜`8`）。
- **太字を使わない**（`font-weight` は 400 統一。`b`/`strong` だけ 500）。段は大きさと文字の濃さで作る。**例外は無い**。
  **書体も 1 本**（`--font-sans`）＋ 等幅（`--font-mono`）＋ 図用（`--font-display`）の3トークンだけ。
  サイトタイトル専用書体 `--font-brand` を持っていた時期があるが 2026-09-05 に廃止済み。
- **字間 0.03em・行間 1.9** をかける。**リンクは色を変えず細いグレーの下線**。
- 囲いは罫より**淡い面（`--bg-soft`）＋大きな角丸（20px）**、ボタン・タグは**ピル**。
  **ヘッダーは罫も影も持たず sticky にしない**。本文カラムは **800px**（読み物は 640px）。
- **過去のデザイン（活字見本帖 / 知識アーカイブ、および GitHub 寄りの「プレーン」案）はどちらも破棄済み**。
  **明朝体・紙色の地・朱のアクセント・青いリンク・`01` 形式のゼロ埋め番号・2px の太罫・太字による強調は使わない**。
  「以前そう決めた」を根拠に差し戻さない。
- **「ただ、そこ」から移すのは構えだけで、色と罫は移さない**。手本の構造はほぼ真っ黒な 1px の罫が
  作っており、色相もわずかに緑み。**黒罫・緑み・黒いフッターは持ち込まない**。
- 2026-09-03 に **TOFT / mud Inc. / ただ、そこ のエッセンスを重ねた**。足したのは4つだけ:
  **①極小の等幅英字ラベル「標識」（`.label-en`。必ず日本語見出しと対にする）／②線だけの巨大な数字
  （`.figure-number`）／③額装＋縦罫でひと区画を割ること（`.masthead`・`.page-header--rail`）／
  ④全幅の帯で区画を割ること（`.band` / `.sheet`）**。いずれも色・太字・装飾を増やさない手段で、
  **新しい要素を1つ足すなら既にあるものを1つ削る**。
- **図版は写真ではなく線画で用意する**。埋まる当てのない写真プレースホルダは置かない
  （`.image-slot` は 2026-09-09 に partial ごと削除済み。**再導入しない**）。
  線画は **五十音円環（`shared/_kana_ring_art`）と放射図（`shared/_radial_art`）の2種だけ**で、
  どちらも実データから描く。**線画は1ページに1枚**（ホームの印だけは看板なので別枠）。
- **ホーム最上部の印はサイト名の読み「ナガイコトバノデータベース」の円環**で、これがロゴを兼ねる
  （別途ロゴ画像を持たない）。**ヘッダーのブランドマークと favicon も同じ円環**
  （`shared/_brand_mark` / `public/icon.svg`）。**favicon の SVG は `prefers-color-scheme` で地と線を反転**
  させ、タブがライトでもダークでも沈まないようにする。色は直書きせずライト/ダークに自動追従させる。
- **動きはサイト全体でホーム最上部の印だけ**: 「ナ」から「ス」へ一筆書きで描くアニメーション
  （1度で止まる）＋ 外周の標識「NAGAI KOTOBA DATABASE」が 80 秒で1周（永続）。
  線の全長は `KanaRing.stroke_length`、回転の中心は `KanaRing::CENTER` をサーバ側から CSS 変数で渡し、
  そのためだけの JS を持たない。**`prefers-reduced-motion: reduce` では完成形を出す**。
  他は hover の色変化（160ms）だけで、スクロール連動・視差・一斉フェードインは入れない。
- **淡さには下限がある**: 静けさを狙って色を薄くしすぎると白飛びして目が滑る。
  **文字は最も弱い `--text-subtle` でも白地 4.5:1（面の上でも 4.5:1）、面・罫は白との差 ΔRGB 19 以上**を確保する。
  色を薄くする変更をしたら**必ず実測して確かめる**（2026-09-03 の計測で、ライトのテキストの 88% が AA 未達だったことがある）。
- **並んだ要素どうしの罫は `border` で作らない**: 親を罫の色で塗り、各要素を面の色で塗って
  **`gap: 1px` の隙間を境界線として見せる**（`display: grid; gap: 1px; background: var(--border)` ＋ 子に `background`）。
  `:first-child` / `+` セレクタでの打ち消しが要らなくなる。**角丸は持たせない**。
  単独の区切り線（章の罫・ツールバーの上下罫など）と `<table>`、`.search-form` は対象外で `border` のまま。
- **罫は二層で持つ**: 淡い罫（`--border`）だけだと稜線がゼロになる。**「章を分ける1本」にだけ
  `--text-muted` を罫の色として使う**（適用は design.md §3 に列挙した4箇所だけ。黒までは濃くしない）。
- **広い単色の面を作らない**: 全高の数割を淡い面で敷くと、中身が平坦に流れて「どこを見ればいいか」が消える。
  面を足すのではなく**外して罫で仕切る**方向で直す。**本文に面を敷く案は2通り試して、どちらも不採用**。
  困りごとは色の不足ではなく「区画の境目が分かりにくい」「中身が浮いて見える」ことなので、**色ではなく罫で解く**。
- **区画は「面の色 ＋ 1px の細罫 ＋ 余白」だけで示す。影は使わない**。**色を持つのはヘッダーとフッター
  （`--bg-soft`）だけで、そのあいだのコンテンツは白（`--surface`）**。面は `--surface` / `--bg-soft` /
  `--bg`（ボタンの塗り）の**3段だけ**。ただし**面は「囲い」ではなく「地層」にする**:
  角丸で四辺を閉じた面を縦に並べると島が散らばって一体感が消えるので、面が要るなら**画面端まで届く帯**にする。
  **この組み方をするのはホームだけ**（`main.container--flush` + `.band` / `.sheet`）。
  ホームの区画は**面ではなく `--border` の 1px の格子**で組む: 区画どうしの横罫（画面端まで通す）＋
  **縦罫3本**（袖と本体を分ける柱 `.band__body` の `border-left` と、区画の左右の額 `.band__inner` の
  `border-inline`。いずれも区画の全高に通す）＋ 見出し行の下罫。**この縦罫が「中身が浮いて見える」を直す要**で、
  宙で途切れさせない。767px 以下では縦罫を3本とも外す。
  **紙全体を貫く縦罫2本の案／ニューモーフィズム／ドロップシャドウの“カード風”はいずれも試作の結果不採用。再提案しない。**
- **標識（`.label-en`）は 12px の塗り**（`--text-subtle`）。**白抜き（アウトライン）にする案は不採用**
  （2026-09-05 オーナー判断）。**白抜きを使うのは `.figure-number` だけ**。
  再検討するなら、白抜きは**指定色ではなく「線の画素そのもの」を測って** AA を確かめること
  （細い線はアンチエイリアスで溶けるので指定色は当てにならない。塗りは従来どおり指定色で評価）。
- **標識は 2 行目に必ず「値」を持たせる**（`1,683 ENTRIES` など）。h1 の英訳を貼っただけの標識は読まれない。
  値は日本語側にも必ず同じ数字を置く。
- **関連データ（ジャンル・品詞・エンティティ・特徴）は雑に並べない**: 必ず専用コンポーネント
  （パンくず／丸タグ・チップ）にし、**検索の絞り込みへの導線**にする。
- CSS は手書き（Sprockets、`tokens → base → layout → components`）。**パフォーマンス最優先**で、
  デザインのために重いフォント / CDN / 過剰な JS を入れない（**web フォントは読まない**・画像遅延・importmap 維持）。
- **管理画面（`/admin`）は「しずか」を引き継がない**（2026-09-06 オーナー指示）。読み物ではなく**作業画面**で、
  見るのはオーナー 1 人。**ページ構成・レイアウト・HTML は公開側と共有したまま、`<body class="is-admin">` の下で
  トークンだけ上書きする**（`app/assets/stylesheets/admin.css`）: 字間 0・行間 1.5・文字と罫を濃く・
  角丸をほぼ直角に・ヘッダーの円環 SVG と英字を消す。個々のコンポーネントには触らない。
  **`.is-admin *` のような全称セレクタで `transition` を潰さない**（スタイル再計算のたびに全要素へ
  マッチして逆に重くなる。実測済み）。

## 重い処理・外部連携
- メール送信・外部 API 呼び出し・重い集計は **ActiveJob で非同期化**する。
- 現状バックグラウンドジョブのバックエンドは未導入（既定の `:async` アダプタで、プロセス内実行）。
  恒常的なジョブ基盤が必要になったら、Rails 8 標準の **Solid Queue** 導入を第一候補として検討・相談する。
- ジョブは**冪等**に設計し、リトライされても問題ないようにする。
- 外部 API 呼び出しには **タイムアウトと例外処理**を必ず入れる。
- 外部コマンド（`mecab` / `rsvg-convert`）への依存は**必ず「無くても機能が止まらない」形**にする
  （読みは空欄で手入力、og:image は既定カードへフォールバック）。依存するテストは skip で通す。

## 可読性・命名
- メソッド・変数・クラス名は**意図が伝わる名前**にする。省略しすぎない。
- マジックナンバー / マジック文字列は定数化、状態は Enum 化する（`genres.level` など）。
  共有する基準値は使う側ではなく**概念の持ち主**に置く（例: 収録基準は `WordSense::MIN_READING_LENGTH`、
  類似度しきい値は `Levenshtein::SIMILARITY_THRESHOLD`）。
- 重複は適度に DRY にする。ただし過度な抽象化は避け、読みやすさを優先する。
- 表示文言は `config/locales`（既定ロケールは `:ja`、`ja.yml`）の i18n（`t(...)`）を使い、ハードコードしない。

## テスト（Minitest）
- 変更には対応するテストを用意する。**正常系だけでなく異常系・境界値**も書く（例: `char_type_pattern` 変換の記号・数字・全角半角）。
- 種類を目的に応じて使い分ける: モデル（`test/models`）/ コントローラ・結合（`test/controllers`・`test/integration`）/ システム（`test/system`、Capybara + Selenium）。
- **1つの振る舞いは1つの層で検証する**。変換規則は値オブジェクト・モデルのテスト、画面の出し分けやリンクは結合テスト（`assert_select`）で書き、別の層で同じことを重ねない。
- **システムテストは JS が無いと成立しない挙動だけに書く**（遅く、Chrome の版で不安定になりやすいため）。同じ画面で確かめる操作は1回の `visit` にまとめる。同じ前提で分けただけの結合テストも1本にまとめ、重いページ（`/stats` など）の GET を重ねない。
- 開発中の確認で役目を終えたテスト（もう無いマークアップの「不在」確認、ルートヘルパ・関連の宣言そのものの確認）は残さない（2026-09-14 に 1002 本を整理した）。
- キャッシュを有効にして検証するときは、書き込み先を差し替える。フラグメントキャッシュ（ビューの `cache`）は `Rails.cache` ではなく起動時に取り込んだ `ActionController::Base.cache_store` に書く（`Rails.cache` だけを差し替えたテストは一度もキャッシュを通っていなかった）。
- フィクスチャは `test/fixtures` を使う。
- 過度なモックで実態を検証できなくならないようにする。
- 時刻・乱数・外部 API は固定（`travel_to` / stub）して、テストを安定させる。
- 実行は `bin/rails test`（単体）/ `bin/rails test:system`（システム）。

## やらないこと / 確認すること
- 仕様が曖昧なまま大きな変更を進めない。不明点は先に確認する。
- 既存の公開 API・ルーティング・DB スキーマを壊す変更は、影響範囲を説明してから行う。
  **公開済みの URL とクエリパラメータ名は世に出ているので変えない**（`?sort=created_desc` など）。
- 不要な Gem を増やさない。追加する場合はメンテ状況とライセンスを確認し、`Gemfile.lock` の更新も忘れない。
- `config/deploy.rb`・`config/puma.rb`・`.github/workflows/` などインフラ/デプロイ設定の変更は影響が大きいので、内容を説明してから行う。
- 検索エンジンから見える挙動（robots・canonical・noindex・sitemap）を変えるときは、
  **URL 空間が無限に広がらないか**を必ず確認する（過去に 2 度クロール事故を起こしている。issues.md Issue 80・81）。
