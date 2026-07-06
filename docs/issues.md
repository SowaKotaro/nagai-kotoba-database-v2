# 実装 Issue リスト（単語収集・解析アプリ）

`docs/schema.sql` を基にした段階的な実装計画。上から実装順。各 Issue = 1 ブランチ = 1 PR を原則とする。

## データモデル概要
- `word` : `word_sense` = 1 : 多（同音異義語に対応）。
- `genres` は隣接リスト（`parent_id`）で 大(level1)→中(level2)→小(level3) の3階層を表現。小分類が決まれば中・大も一意に辿れる。
- `word_senses.genre_id` は末端（小分類=level3）を指す。**登録時は必ず大→中→小まで選択する**（中・大は `parent_id` を辿って一意に復元）。
- ジャンルは日本十進分類法(NDC)を基にした柔軟な階層。各階層の子は10種に収まらないため、**数値の分類コード列は持たない**（名前＋階層のみ）。
- `linguistic_features` は `word_sense_features` 経由で語義と多対多。特徴は単語の**該当部分ごと**に付与する（`target`＝表層の一部 / `target_reading`＝その読み）。
- 生成カラム（STORED）: `reading_length` / `first_char` / `last_char`（SQL 側）。`char_type_pattern`・`rhythm_pattern` は Ruby 側で生成。
- 想定規模: 1万レコード程度。

## 横断方針
- **照合順序(collation)**: 日本語検索が中心のため、全テーブルを **`utf8mb4_0900_ai_ci`** に統一する方針。既存の `admins` / `sessions`（`utf8mb4_general_ci`）も変更マイグレーションで揃える（Issue 1 で対応 or 別途）。
- 閲覧は全世界に公開、登録・編集・削除は管理者のみ（[[CLAUDE.md]] 参照）。
- インデックスのキー長対策で、`utf8mb4` の長い文字列カラムは先頭191文字の prefix index を使う（`surface(191)` など）。

---

## Issue 1: 設計ドキュメント整備とスキーマ方針確定 ★最初のブランチ
- [x] `docs/schema.sql` を取り込む
- [x] 本 Issue リスト（`docs/issues.md`）を作成
- [x] `CLAUDE.md` を作成（ドメイン／公開方針／スキーマ方針を反映）
- 照合順序の方針確定・既存テーブルの扱いは **Issue 2** へ、`char_type_pattern` の変換仕様メモは **Issue 4** へ、`rhythm_pattern` の変換仕様メモは **Issue 5** へ移動。

## Issue 2: ジャンル(genres)マスタ ― 3階層・自己参照
- [x] migration: `parent_id`(自己参照FK), `level`, `name`, `UNIQUE(parent_id, name)`, `index(level)`
- [x] model `Genre`: `belongs_to :parent`(optional) / `has_many :children`、`name` presence・`(parent_id, name)` 一意
- [x] level と parent の整合性バリデーション、末端(level3)から祖先(中・大)を辿るメソッド（`self_and_ancestors` / `root_genre`）
- [x] 分類コード列は設けない（名前＋階層のみ）
- [x] 照合順序の方針確定（`utf8mb4_0900_ai_ci` 統一）と、既存テーブル（`admins` / `sessions`）の扱いを決定 ※Issue 1 から移動
  - ローカルは MariaDB で `utf8mb4_0900_ai_ci` 非対応のため、CI/本番と同じ MySQL 8.4 を `docker compose`（ホスト3307）で用意し接続先を切替。
  - 既存 `admins` / `sessions` は本 Issue のマイグレーションで `utf8mb4_0900_ai_ci` に変換し統一。
- 依存: なし

## Issue 3: 単純マスタ3種（entity_types / parts_of_speech / linguistic_features）
- [x] 各 migration: `name`, `UNIQUE(name)`
- [x] 各 model: `name` presence・uniqueness
- [x] `parts_of_speech` は不規則複数形のため `config/initializers/inflections.rb` に屈折ルールを追加（`PartOfSpeech` → `parts_of_speech`）
- 依存: なし（Issue 2 と並行可）

## Issue 4: words テーブル ― 表層形と char_type_pattern 生成
- [x] migration: `surface`, `char_type_pattern`, `UNIQUE(surface(191))`, `index(char_type_pattern(191))`
- [x] model `Word`: `has_many :word_senses`、`surface` presence・uniqueness
- [x] `char_type_pattern` 生成ロジック（漢字→漢 / ひらがな→あ / カタカナ→ア / 英字→A / その他→@）を surface から生成（値オブジェクト `CharTypePattern`、`before_validation` で自動セット）
- [x] 生成ロジックのユニットテスト（記号・数字・全角半角の境界）
- [x] `char_type_pattern`（漢/あ/ア/A/@）の変換仕様メモを残す（[`docs/char_type_pattern.md`](char_type_pattern.md)）※Issue 1 から移動
  - 長音符 `ー`/`ｰ` はカタカナ(`ア`)扱い、`々` は漢字(`漢`)扱いと決定。
- 依存: なし

## Issue 5: word_senses テーブル ― 語義・生成カラム・rhythm_pattern
- [x] migration: FK `word_id`/`genre_id`/`entity_type_id`/`part_of_speech_id`、`reading`, `rhythm_pattern`, `meaning`
- [x] STORED 生成カラム（`t.virtual ... stored: true`）: `reading_length` / `first_char` / `last_char` と対応 index
- [x] model `WordSense`: 各 `belongs_to`（entity_type/part_of_speech は optional）、`reading` presence
- [x] `genre_id` は **level3(小分類) のみ許可**するバリデーション（必ず小分類まで選ぶ運用）
- [x] `rhythm_pattern` 生成（読み→ローマ字、Ruby 側）。かな→ローマ字変換の方針決定
  - **ヘボン式**を採用。**長音は母音をそのまま展開**（`とうきょう→toukyou`、`カレー→karee`）。値オブジェクト `RhythmPattern` + `before_validation` で自動セット。
- [x] `rhythm_pattern`（ローマ字）の変換仕様メモを残す（[`docs/rhythm_pattern.md`](rhythm_pattern.md)）※Issue 1 から移動
- 依存: Issue 2・3・4

## Issue 6: word_sense_features ― 語義 × 言語学的特徴（多対多）
- [x] migration: 中間テーブル、両 FK、`target`（該当部分・表層）/ `target_reading`（該当部分の読み）
- [x] 特徴は単語の**該当部分ごと**に付与する（例:「硫黄島からの手紙」に 連濁:硫黄島 / 熟字訓:硫黄 / 連濁:手紙）。
  このため `UNIQUE(word_sense_id, linguistic_feature_id, target)` とし、同じ語義×特徴でも該当部分が違えば複数登録可
- [x] `WordSense has_many :linguistic_features, through:`、三つ組の重複防止（中間モデルの uniqueness ＋ DB 複合ユニーク）
- [x] `target` は親 `word.surface`、`target_reading` は `word_senses.reading` の部分文字列であることを検証
- [x] `LinguisticFeature` からも `word_senses, through:` で辿れる。参照中のマスタは削除不可（`restrict_with_error`）
- 依存: Issue 3・5

## Issue 7: 管理者用 CRUD（登録・編集・削除）
- [x] 認証必須の管理コントローラ（`Admin::` 名前空間 = `/admin/words`。`Admin::BaseController` は `ApplicationController` を継承し既定で認証必須）
- [x] words / word_senses / word_sense_features のフォーム（**1画面フル入れ子**。`accepts_nested_attributes_for` ＋ Stimulus `nested-form` で語義・特徴の行を動的に追加/削除）
- [x] 言語学的特徴は**該当部分つき**（`target` / `target_reading`）で複数登録（Issue 6 の再設計に対応）
- [x] ジャンルは **大→中→小の依存ドロップダウン**（Stimulus `genre-cascade` ＋ `Admin::GenresController#children` の JSON）。送信は小分類(`genre_id`)のみ
- 依存: Issue 4・5・6
- 補足: Stimulus の DOM 操作（行の追加/削除・カスケード）はシステムテスト（Capybara/Selenium）で確認する想定。サーバ側（認可・ネスト保存・バリデーション）は結合テストでカバー済み。

## Issue 8: 公開閲覧（一覧・詳細）
- [x] 未認証で閲覧可（`allow_unauthenticated_access`）の一覧・詳細（トップレベル `WordsController#index/#show`。書き込みは admin 側に限定）
- [x] word とその語義群、ジャンル階層（大 > 中 > 小）・品詞・エンティティタイプ・言語学的特徴（該当部分つき）の表示
- [x] 一覧は gem を足さず軽量ページネーション（`limit`/`offset` ＋ `page` パラメータ、前へ/次へ）。1万件想定に配慮
- 依存: Issue 4・5（6 があれば特徴も）

## Issue 9: 検索・絞り込み機能
- [x] `reading_length`（下限/上限）・先頭/末尾文字・`char_type_pattern`（完全一致）・ジャンル階層・品詞・エンティティタイプ・言語学的特徴・`rhythm_pattern`（部分一致）での絞り込み
- [x] 生成カラム／インデックスを活用（`WordSense` のスコープ群。`char_type_pattern` は `words` と join）
- [x] 公開の検索ページ `GET /search`（`SearchesController#index`、未認証可）。ロジックはクエリオブジェクト `WordSenseSearch` に集約
- [x] キーワード検索 `q`（表層形・読みの部分一致。ヘッダー常設検索・ホームの検索窓の入口）※デザイン改修時に追加
- [x] ジャンルは階層セレクト（大/中/小のどれを選んでも配下の小分類で絞り込み）。結果は語義単位で一覧＋軽量ページネーション
- 依存: Issue 5（必要に応じ 6・8）

## Issue 10: マスタのインライン追加（単語登録画面から完結）
- [ ] 単語の登録・編集画面（Issue 7）から**別ページに遷移せず**、セレクトの選択肢を新規追加できるようにする。
  - 対象マスタ: 中分類/小分類（ジャンル）・品詞・エンティティタイプ・言語学的特徴。
- [ ] 各マスタ用の軽量な create アクション（`Admin::` 名前空間）＋ **Turbo Stream** で対象 `<select>` に新しい `<option>` を追加し、その場で選択状態にする。
- [ ] ジャンルの中分類/小分類は**現在選択中の親（大/中）配下**に作成する（親 `id` を送る。カスケードと整合）。
- [ ] 追加 UI は `<dialog>` もしくは Turbo Frame をその場で開く方式（小さな Stimulus）。フルページ遷移させない。
- 依存: Issue 7
- 目的: 「別ページで追加 → 戻って選択」という手間を無くし、単語登録フロー内で完結させる。

## Issue 11: 拡張データ（読み指標・語種・別表記）
言葉に紐づく解析データを増やす。今回はデータ層（マイグレーション・モデル・値オブジェクト・seed・バックフィル・テスト）まで。検索/表示など画面機能は含めない（別 Issue）。
- [x] `word_senses` に **モーラ数 `mora_count`**（拗音「きゃ」は1拍。`reading_length` とは別軸）を追加。値オブジェクト `MoraCount` ＋ `before_validation` で reading から生成（Ruby 側・NULL 許容）。
- [x] `word_senses` に **母音パターン `vowel_pattern`**（`rhythm_pattern` から母音 aiueo のみ抽出）を追加。値オブジェクト `VowelPattern`（`rhythm_pattern` 生成の後に生成）。
- [x] **語種マスタ `word_origins`**（和語/漢語/英語/フランス語…）。「外来語」で束ねず言語ごとに切り分ける開いた集合。単純マスタ（`name` + `UNIQUE`）。seed 投入。
- [x] **語義 × 語種の多対多 `word_sense_origins`**（中間）。混種語（例: 歯ブラシ = 和語 + 英語）に対応し 1 語義に複数付与可。`UNIQUE(word_sense_id, word_origin_id)`。参照中の語種は `restrict_with_error`。
- [x] **別表記 `word_sense_variants`**（語義に 1:多）。その語義にだけ付く別の表記。読みも変わりうるため `reading` を保持（任意）。`UNIQUE(word_sense_id, surface)`。
- [x] `WordSense` に多対多（`word_origins, through:`）・`has_many :word_sense_variants` と `accepts_nested_attributes_for` を追加。
- [x] 既存行向けバックフィルタスク `backfill:reading_metrics`（rhythm/vowel/mora を reading から再生成、冪等）。
- [x] 値オブジェクト（境界値）・各モデルのユニット/バリデーションテスト、フィクスチャ整備。
- マイグレーション: `AddReadingMetricsToWordSenses` / `CreateWordOrigins` / `CreateWordSenseOrigins` / `CreateWordSenseVariants` の4本。
- 依存: Issue 5（語義）・Issue 3（マスタの作法）

## Issue 12: 高速アノテーション・コンソール
1語集中キュー型の管理 UI。既存 `/admin/words`（フル入れ子フォーム）とは**併存**。モックで UX 確定後に実装（`docs/design.md` 準拠）。
- [x] `words.annotated_at` を追加（`AddAnnotatedAtToWords`）。**未注釈キュー** = `Word.unannotated`（`annotated_at` が NULL）。保存で現在時刻をセット。
- [x] `Admin::AnnotationsController`（index=最初の未注釈へ誘導 / show=コンソール / update=保存して次の未注釈へ）。**Turbo Frame** でキュー送り（フルリロードなし・`turbo_action: advance` で履歴追従）。
- [x] **ドロップダウン全廃**。語種＝複数チップ（`word_origin_ids`）、品詞・エンティティ＝単一チップ（ラジオ）、ジャンル＝**段階表示**（大→中→小、選ぶと下位が出現）。チップは隠し input＋CSS `:has()` で極力 JS レス。
- [x] **言語学的特徴の該当部分をキーボードなしで指定**: 単語／読みの文字を「始点→終点タップ」（宿泊予約のチェックイン/アウト式）で範囲選択（`feature-range` Stimulus）。スマホ/タブレット対応。
- [x] **マスタのその場追加**（Issue 10 相当）: 語種・品詞・エンティティ・ジャンル（各階層）を画面遷移せず JSON POST で追加し即選択（`inline-add` / `genre-picker` Stimulus、`Admin::WordOrigins/PartsOfSpeech/EntityTypes/Genres#create`）。
- [x] **語義を追加**: 語種・品詞・特徴を引き継ぎ、読み・意味・ジャンル・エンティティ・別表記を空にした語義を複製（`sense-cloner` Stimulus）。
- [x] 別表記は語義ごとにネストで登録。CSS は `annotate.css`（manifest に追加）。i18n・スモークテスト（描画＋ネスト保存＋その場追加）。
- 依存: Issue 11（語種・別表記）・Issue 5/6/7（語義・特徴・admin CRUD の作法）
- 補足: チップ操作・範囲タップ・段階ジャンルなどの DOM 挙動はシステムテスト（未整備）で確認する想定。サーバ側は結合テストでカバー済み。

---

# SEO・LLMO 改善イシュー（2026-07-06 分析）

検索エンジン・LLM（AI 検索）経由の流入最大化の観点でリポジトリ全体を分析した結果のバックログ。
既存 Issue 1〜12 の続きとして採番。着手時は従来どおり **1 Issue = 1 ブランチ = 1 PR**。

## 現状サマリー

### 技術構成（クローラビリティの前提）
- 全ページ ERB による **SSR**（+ Turbo Drive）。JS 無効でも全コンテンツが HTML に含まれ、クローラビリティ自体は良好。CSR 依存なし。追加の SSG は不要。
- 公開面は 4 種のみ: ホーム（`/`）・単語一覧（`/words`。クエリパラメータでファセット絞り込み）・単語詳細（`/words/:id`）・詳細検索フォーム（`/search`）。
- 未注釈語は 404（`WordsController#show` が `Word.annotated` で絞る）で、公開品質のゲートは既にある。

### 観点別評価

**A. 技術SEO** — 基礎がほぼ未整備（未公開の今が入れどき）。
- 良い点: SSR、`lang="ja"`、パンくず UI、`font-display: swap`、`force_ssl`、軽量ページネーション（prev/next が実リンク）。
- 問題点: meta description / OGP / canonical が一切ない（`app/views/layouts/application.html.erb` は title のみ）。`public/robots.txt` は雛形コメントのみで sitemap.xml も無い。ファセット URL（`/words?genre_id=…` 等）が全組み合わせで title「単語一覧」固定のまま無限に増殖し重複コンテンツ化する。構造化データなし。`public/favicon.ico`・`apple-touch-icon.png`・`apple-touch-icon-precomposed.png` が **0 バイトの空ファイル**。
- URL 設計の判断: `/words/:id`（数値 ID）は安定していて可。日本語スラッグは URL エンコードで可読性・共有性が落ちるため、**ID 維持 + title/メタ/構造化データで補う**方針を推奨（イシュー化しない）。

**B. LLM検索最適化** — ページ単体の構造は良いが「自己完結性」と機械可読出力が不足。
- 良い点: `<ruby>` による読み表示、`<dl>` による属性表示、1 語 1 URL、title にサイト名が入る。
- 問題点: llms.txt なし。`meaning`（意味）が任意入力のため**散文ゼロのページ**が生まれうる（LLM が引用できる定義文がない）。JSON-LD・公開 API なし（jbuilder は Gemfile にあるが未使用）。サイト概要を語る恒久ページ（About）が無くフッター文言のみ。

**C. HTML構造・セマンティクス** — 概ね良好。
- 良い点: 見出し階層（h1→h2）、`<dl>`/`<ruby>`、`aria-label`・`aria-current`・`aria-expanded`、インライン SVG に `aria-hidden`。
- 軽微な問題: 一覧行（`words/_entry_row`）が div/span 構成（ul/li が自然）。読み（reading）が `<ruby>` の `rt` にしか存在せず、dt/dd としての明示がない（Issue 16・18 で吸収）。

**D. 情報設計・内部リンク** — 詳細ページ発のファセットリンクは充実。**入口（ハブ）と単語間リンクが不足**。
- 良い点: 詳細ページからジャンル各階層・品詞・エンティティ・語種・文字数・モーラ・先頭/末尾文字への実リンク。
- 問題点: ジャンル階層・エンティティ等の一覧ページ（ハブ）が存在せず、ファセット面へのクロール導線が単語詳細経由のみ。検索フォームのチップは checkbox でありリンクではないためクローラが辿れない。単語→単語の「関連語」リンクがゼロでトピッククラスターが形成されない。

**E. コンテンツ・データ品質** — スキーマは正規化・拡張性とも良好。ページの「散文量」が弱点。
- 良い点: word/word_sense 分離、別表記（word_sense_variants）で表記ゆれ対応、語種の多対多、生成カラム、管理者精査型の運営（E-E-A-T 的に明記する価値あり）。
- 問題点: `meaning` 任意のため薄いページになりうる。用例・出典のフィールドがない。ユーザー投稿は方針として持たない（公開側にアカウント機能を作らない方針と整合。イシュー化しない）。

**F. グロース・エンゲージメント** — 検索・絞り込みと「今日の一語」（`HomeController#featured_word`、日替わり決定的）は実装済み。OGP 画像・シェア導線・フィード・埋め込みは無い。

**G. 運用・技術基盤** — CI・テスト・セキュリティスキャン（rubocop/brakeman/bundler-audit/importmap audit）は整備済み。**計測と HTTP キャッシュがゼロ**。
- 問題点: アナリティクス / Search Console 検証タグなし。`fresh_when`/ETag・fragment cache なし（ホームは毎リクエスト COUNT 3 本）。production の `config.hosts` 未設定。`public/404.html` 等が Rails 既定の英語ページ。CSP 初期化子がコメントアウトのまま（セキュリティ強化として別途検討。Google Fonts 利用中は directive 調整が必要）。

**H. その他の気づき**
- `Word.keyword` スコープ（`app/models/word.rb`）は未使用（検索は `WordSense.keyword` に集約済み）。掃除候補（PR ついでの削除で可、イシュー化しない）。
- 詳細ページの「No. %{id}」は DB 連番の露出だが実害なし。

## イシュー一覧

## [bug] Issue 13: favicon.ico / apple-touch-icon が 0 バイトの空ファイル
- 種別: bug
- 観点: A / H
- 背景・現状: `public/favicon.ico`・`apple-touch-icon.png`・`apple-touch-icon-precomposed.png` が 0 バイト。ブラウザ・iOS・クローラが空ファイルを受け取る。Google は検索結果にファビコンを表示するため、欠けると SERP 上の見た目とクリック率に響く。`public/icon.svg`（朱の印章）は正常でレイアウトから参照済み。
- 提案内容: `icon.svg` から 32/48px の `favicon.ico` と 180px の `apple-touch-icon.png` を生成（rsvg-convert か ImageMagick）して差し替え。`apple-touch-icon-precomposed.png` は削除で可。
- 期待効果: SERP・ブラウザタブ・共有時のブランド表示が正常化。
- Impact: Low
- Effort: Low
- 優先度: P1（数十分で終わる quick win。公開前に）

## [improvement] Issue 14: メタ情報の動的生成（description・OGP・canonical）
- 種別: improvement
- 観点: A / B
- 背景・現状: `app/views/layouts/application.html.erb` は `<title>` のみで、meta description・OGP（og:title/description/type/url/site_name/image）・twitter:card・canonical が一切ない。SERP のスニペットが本文冒頭の機械的抜粋になり、SNS/チャット共有時のプレビューも出ない。
- 提案内容: gem を足さずヘルパー + `content_for` で実装。(1) `ApplicationHelper` に `page_description` / `canonical_url` を用意しレイアウトで出力（既定値はサイト説明 = `ja.yml` の `home.index.description` を流用）。(2) `words#show` は Issue 18 のリード文を description に流用。(3) og:site_name=ブランド名、og:locale=ja_JP、既定の og:image として静的画像 1 枚（icon.svg ベースの 1200×630 PNG）を `public/` に用意。(4) canonical は `https://nagai-kotoba-database.jp` を正とする（確定事項 1）。
- 期待効果: SERP スニペット・CTR 改善、SNS/LLM チャットでの共有プレビュー成立、重複 URL の正規化。
- Impact: High
- Effort: Medium
- 優先度: P0

## [feature] Issue 15: sitemap.xml の動的生成と robots.txt の整備
- 種別: feature
- 観点: A
- 背景・現状: sitemap が無く、`public/robots.txt` はコメント 1 行のみ。単語詳細への導線は一覧ページネーション経由のみで、公開直後のインデックス速度が出ない。`/admin` などのクロール制御も未指定。
- 提案内容: (1) `SitemapsController`（`allow_unauthenticated_access`）で `/sitemap.xml` を動的生成: 静的ページ（`/`・`/words`・About 等）+ `Word.annotated.find_each`（lastmod=`updated_at`）。1 万語想定なら 1 ファイル（上限 5 万 URL）で足り、gem 不要。`expires_in` で 1 日キャッシュ。(2) `robots.txt` に `Sitemap:` 行と `Disallow: /admin` `Disallow: /session` `Disallow: /search` を追記（`/search` の扱いは Issue 17 の方針と揃える）。
- 期待効果: 公開直後から全単語ページを確実・高速にインデックスさせる。クロールバジェットの浪費防止。
- Impact: High
- Effort: Low
- 優先度: P0

## [feature] Issue 16: 構造化データ（JSON-LD: DefinedTerm・BreadcrumbList・WebSite）
- 種別: feature
- 観点: A / B
- 背景・現状: schema.org マークアップが一切ない。辞書サイトは `DefinedTerm`/`DefinedTermSet` が素直に当てはまるドメインで、パンくず UI（`shared/_breadcrumbs`）も既にあるのに `BreadcrumbList` が無い。
- 提案内容: ヘルパー（例 `StructuredDataHelper`）で `<script type="application/ld+json">` を出力。(1) `words#show`: `DefinedTerm`（`name`=surface、`description`=リード文/meaning、読みは `alternateName` か `phoneticText`、`inDefinedTermSet`=サイト全体の `DefinedTermSet`）を語義ごとに。(2) 全ページ: `BreadcrumbList`（`_breadcrumbs` に渡す items 配列を流用できる形にする）。(3) レイアウト: `WebSite` + `SearchAction`（`/words?q={search_term_string}`）。
- 期待効果: リッチリザルト・サイトリンク検索ボックスの獲得可能性、LLM/AI 検索がページ構造を誤りなく解釈して引用する確度の向上。
- Impact: High
- Effort: Medium
- 優先度: P0

## [improvement] Issue 17: ファセット付き一覧・検索ページのインデックス方針（noindex / 動的 title）
- 種別: improvement
- 観点: A
- 背景・現状: `/words` はクエリパラメータの全組み合わせ（`genre_id`×`first_char`×`page`×…）でページが無限に増殖するのに、title は「単語一覧」固定（`app/views/words/index.html.erb`）。重複 title の大量発生とクロールバジェット浪費で、サイト全体の評価を下げるリスクがある。`/search`（フォームページ）にも指定がない。
- 提案内容: (1) **単一条件**のファセット（ジャンル/品詞/エンティティ/語種/先頭文字のいずれか 1 つ）はインデックス許可し、`applied_search_conditions`（`SearchesHelper`）を流用して title・h1・description を「◯◯の長い言葉一覧」等に動的化。(2) 複数条件・`q`・`page` 2 以降は `<meta name="robots" content="noindex,follow">`。(3) `/search` は noindex。(4) canonical はパラメータをソート正規化した自身。判定ロジックは `WordSenseSearch` に載せる。
- 期待効果: 重複コンテンツの抑止と、価値あるファセット面（≒カテゴリページ）の検索流入獲得の両立。
- Impact: High
- Effort: Medium
- 優先度: P0

## [improvement] Issue 18: 単語詳細に自己完結のリード文（定義文）を自動生成
- 種別: improvement
- 観点: B / E
- 背景・現状: `words/show.html.erb` は `meaning` が空だと散文が 1 文も無いページになる（読み・タグ・数値のみ）。LLM が「◯◯とは」に答えるときに引用できる文が存在せず、SEO 的にも薄いページと判定されやすい。
- 提案内容: 構造化データから決定的に組み立てるリード文ヘルパー（例 `word_lead_sentence(word)`）を追加し、h1 直下に表示。例: 「「天上天下唯我独尊」は、読み「テンジョウテンゲユイガドクソン」（14文字・12モーラ）の日本語の長い言葉。ジャンルは 哲学・宗教 > 仏教。」`meaning` があれば続けて表示。同じ文を Issue 14 の meta description・Issue 16 の `description` に流用する。
- 期待効果: 全単語ページが「単体で定義を完結」し、AI 検索・強調スニペットに引用可能になる。薄いページの根絶。
- Impact: High
- Effort: Low
- 優先度: P0

## [feature] Issue 19: アナリティクスと Search Console の導入
- 種別: feature
- 観点: G
- 背景・現状: レイアウトに計測タグが無く、Search Console の所有権確認も未実施。公開後にどのクエリ・どのファセットで流入しているか観測できず、以降の全施策の効果検証が不能。
- 提案内容: (1) **GA4 を導入（確定事項 2）**。gtag.js は `send_page_view: false` で読み込み、Turbo Drive 対応として `turbo:load` で `page_view` イベントを送る（Turbo 遷移はフルロードでないため、既定のままだと 2 ページ目以降が計測されない）。(2) Search Console の所有権確認（DNS レコード推奨）+ sitemap（Issue 15）送信。(3) Bing Webmaster Tools も登録(Copilot/ChatGPT 検索の情報源)。
- 期待効果: 流入クエリ・インデックス状況の観測に基づく改善サイクルの確立。
- Impact: High
- Effort: Low
- 優先度: P0

## [feature] Issue 20: About ページ（サイト概要・収録基準・運営方針・ライセンス）
- 種別: feature
- 観点: B / E
- 背景・現状: サイトの目的・収録基準・データの精査方針を語る恒久ページが無く、フッターの 2 文（`layouts.footer.about`）のみ。検索エンジンの E-E-A-T 評価にも、AI 検索が「このサイトは何か」を要約・出典明示する際にも参照先が無い。
- 提案内容: `PagesController#about`（`/about`、`allow_unauthenticated_access`）を追加。内容: サイトの目的／収録基準（**読み 10 文字以上**。確定事項 3）／全件を運営者が精査して登録している旨（フッター文言の昇格）／データの利用条件（確定事項 4）／連絡先。ヘッダーまたはフッターから恒久リンク。
- 期待効果: E-E-A-T シグナルの明示、AI 検索での出典説明の安定化、llms.txt（Issue 24）や API 案内の置き場所確保。
- Impact: Medium
- Effort: Low
- 優先度: P1

## [feature] Issue 21: ジャンル階層のハブページ（/genres）
- 種別: feature
- 観点: D / A
- 背景・現状: ジャンルの一覧ページが公開側に存在しない。ファセットリンクは単語詳細ページ内にしかなく、検索フォームのジャンルはチェックボックス（`searches/_genre_filter`）でクローラが辿れない。全ジャンル面へ到達する静的なクロール経路が無い。
- 提案内容: 公開 `GenresController#index`（`/genres`）を追加。大→中→小のツリーを `Genre.order(:name).group_by(&:parent_id)`（`SearchesController#load_filter_masters` と同じ形）で描画し、各分類に公開語義数（`WordSense.published` を genre_id 群で group count）を添えて `words_path(genre_id:)` へリンク。ヘッダー/フッターのナビに追加。デザインは `docs/design.md` §5.5 のパンくず/タグ規約に従う。
- 期待効果: 全ファセット面への安定したクロール導線、「ジャンル名+長い言葉」系クエリの受け皿、回遊性向上。
- Impact: High
- Effort: Medium
- 優先度: P1

## [feature] Issue 22: 50音・文字数の索引ページ（ブラウズ導線）
- 種別: feature
- 観点: D
- 背景・現状: 「先頭文字」「読みの文字数」での探索は検索フォーム経由のみで、リンクとして辿れる索引が無い。辞書サイトの定番導線（あかさたな索引）が欠けている。
- 提案内容: 索引ページ（例 `/words/browse` か `/index` 相当の 1 ページ）を追加。`SearchesHelper::KANA_COLUMNS` を流用した五十音表（各文字 → `words_path(first_char:)`、件数つき）と、読み文字数別リンク（10〜30 文字、件数つき）を並べる。件数は `WordSense.published.group(:first_char).count` 等で 1 クエリ + キャッシュ。
- 期待効果: クロール経路の多様化、「◯文字の言葉」「◯から始まる長い言葉」系クエリの受け皿。
- Impact: Medium
- Effort: Low
- 優先度: P1

## [feature] Issue 23: 単語詳細に「関連語」セクション（単語間の内部リンク）
- 種別: feature
- 観点: D / B
- 背景・現状: `words#show` からのリンクはファセット一覧行きのみで、**単語→単語の直接リンクがゼロ**。トピッククラスターが形成されず、クローラ・LLM・ユーザーのいずれにとっても回遊が 1 ホップで途切れる。
- 提案内容: `words#show` 下部に「関連語」を追加: 同じ小分類ジャンルの語 / 同じ読み文字数の語 / 同じ先頭文字の語 を各数件（自身を除外、`order(:id)` 等の決定的順序、インデックス済みカラムのみ使用）。各ブロック末尾に「もっと見る → ファセット一覧」。表示は `docs/design.md` の墨枠タグ/一覧行コンポーネントに従う。
- 期待効果: 内部リンクグラフの形成による全ページのクロール頻度・評価向上、直帰率低下、LLM の関連語収集への対応。
- Impact: High
- Effort: Medium
- 優先度: P1

## [feature] Issue 24: llms.txt の提供
- 種別: feature
- 観点: B
- 背景・現状: `/llms.txt`（LLM 向けサイト案内の事実上の標準）が無い。AI クローラがサイト構造・利用条件を把握する足がかりが無い。
- 提案内容: `/llms.txt` を配信(内容が About・収録基準に依存するためコントローラ経由を推奨、静的でも可)。内容: サイト概要(1段落)／収録基準／主要 URL(`/words`・`/search`・`/genres`・`/about`・sitemap・JSON API)／引用時のサイト名表記・ライセンス。Issue 20 と文言を共有。
- 期待効果: AI 検索・エージェントからの発見性と正確な引用（サイト名の露出）の向上。
- Impact: Medium
- Effort: Low
- 優先度: P1

## [feature] Issue 25: 公開 JSON API（単語詳細・一覧の .json）
- 種別: feature
- 観点: B / F
- 背景・現状: データの機械可読出力が無い。Gemfile に jbuilder があるが未使用。LLM・研究者・開発者がデータを参照する経路が HTML スクレイピングしかない。
- 提案内容: `words#show`/`#index` に `format.json` を追加し、jbuilder テンプレート（`app/views/words/show.json.jbuilder` 等）で 表層形・語義（読み・意味・ジャンル階層・品詞・エンティティ・語種・特徴・別表記・各種指標）を返す。読み取り専用のため認可不要（`annotated` スコープは HTML と共通）。一覧はページネーションをそのまま反映。About / llms.txt から案内し、レスポンスにライセンス表記（確定事項 4）を含める。
- 期待効果: LLM・外部サービスからの参照可能性向上、被リンク獲得の種。
- Impact: Medium
- Effort: Medium
- 優先度: P1

## [improvement] Issue 26: 公開ページの HTTP キャッシュ・fragment cache
- 種別: improvement
- 観点: G / A
- 背景・現状: `fresh_when`/ETag が無く、全公開ページを毎回フル生成。ホームは毎リクエスト COUNT を 3 本発行（`HomeController#index`）、`words#index` も毎回 `scope.count`。1 万語 + クローラ流量なら現構成でも耐えるが、CWV（TTFB）と省リソースの改善余地が大きい。
- 提案内容: (1) `words#show` に `fresh_when(@word)`（関連の更新で `updated_at` が動くよう `word_senses` 等に `touch: true` を追加）。(2) ホームの統計 3 カウントを `Rails.cache.fetch`（短 TTL）に。(3) `config.cache_store` を明示（まずは `:memory_store` で十分。恒常化なら Solid Cache を検討・相談）。(4) sitemap（Issue 15）にも `expires_in`。
- 期待効果: TTFB 短縮（CWV 改善）、クローラ大量アクセス時のサーバ負荷低減、304 応答によるクロール効率化。
- Impact: Medium
- Effort: Medium
- 優先度: P1

## [improvement] Issue 27: config.hosts 設定と canonical ホストへの 301 統一
- 種別: improvement
- 観点: G / A
- 背景・現状: `config/environments/production.rb` の `config.hosts` がコメントアウトのままで Host ヘッダ保護が無効。また www あり/なし・IP 直アクセスの正規化が無く、同一コンテンツが複数ホストで応答すると重複コンテンツになる。本番ドメインは `nagai-kotoba-database.jp` で確定（確定事項 1）。現在は旧システムが `nagai-kotoba-database.com` で稼働中で、データ移行完了後に nginx で com → jp のリダイレクトを設定予定。
- 提案内容: (1) `config.hosts` に `nagai-kotoba-database.jp` を設定（`/up` は `host_authorization` の exclude で除外）。(2) nginx 側で www・IP 直アクセスを canonical ホストへ 301。(3) `config.assume_ssl = true` の有効化も確認。(4) **com → jp の移行**: 旧 .com サイトが検索エンジンにインデックス済みの場合、ドメイン単位の一括リダイレクトではなく可能な範囲で **URL 単位の 301 マッピング**（旧単語ページ → 対応する新 `/words/:id`）にし、Search Console の「アドレス変更」ツールで移行を通知する（旧サイトの評価・被リンクを引き継ぐため）。旧サイトが未インデックスならドメイン単位 301 のみで可。インフラ設定変更なので影響範囲を説明の上で実施。
- 期待効果: 重複ホストの排除（canonical と併せて評価の集約）、旧ドメインからの評価引き継ぎ、セキュリティ強化。
- Impact: Medium
- Effort: Low（URL 単位マッピングが必要な場合は Medium）
- 優先度: P1（移行タイミングに合わせて）

## [feature] Issue 28: 新着単語の Atom フィード
- 種別: feature
- 観点: F / B
- 背景・現状: RSS/Atom フィードが無い。再訪導線がブックマークのみで、フィードリーダー・各種クローラの更新検知手段が無い。
- 提案内容: `words#index` に `format.atom`（`index.atom.builder`）を追加し、注釈済みの新着（`annotated_at` 降順）20 件を配信。エントリ本文は Issue 18 のリード文を流用。レイアウトに `<link rel="alternate" type="application/atom+xml">`（autodiscovery）を追加。
- 期待効果: 再訪・購読の獲得、更新の外部通知、LLM クローラの更新検知。
- Impact: Low
- Effort: Low
- 優先度: P2

## [feature] Issue 29: OGP 画像の動的生成（単語ごと）
- 種別: feature
- 観点: F / A
- 背景・現状: og:image が無い（Issue 14 で静的 1 枚は入るが、単語ごとの画像ではない）。「言葉そのものが主役」のデザインは OGP 画像との相性が良く、共有時の CTR を大きく左右する。
- 提案内容: 単語詳細ごとに 1200×630 の画像を生成。実装案: 紙×墨×朱デザインの SVG テンプレート（巨大明朝で表層形 + 読み + サイト名）を ERB で組み、libvips（`image_processing` gem 追加）か rsvg-convert で PNG 化。生成タイミングはアノテーション保存時 or 初回リクエスト時 + ファイルキャッシュ。フォント埋め込みの検証が必要。
- 期待効果: X・Slack・チャット AI での共有時の視認性・CTR 向上。
- Impact: Medium
- Effort: High
- 優先度: P2

## [feature] Issue 30: シェア導線（X 共有リンク・URL コピー）
- 種別: feature
- 観点: F
- 背景・現状: 詳細ページに共有機能が無い。長い言葉は「見せたくなる」コンテンツで、共有の摩擦は少ないほど良い。
- 提案内容: `words#show` に X 共有リンク（`https://x.com/intent/post?text=…&url=…`、テキストはリード文）と URL コピー（小さな Stimulus コントローラ + `navigator.clipboard`）を追加。アイコンは `shared/icons` 流儀のインライン SVG（絵文字・アイコンフォント禁止の規約に従う）。
- 期待効果: SNS 経由の被リンク・言及の獲得（SEO の間接シグナル + 直接流入）。
- Impact: Low
- Effort: Low
- 優先度: P2

## [improvement] Issue 31: Web フォントのセルフホスト化
- 種別: improvement
- 観点: A / G
- 背景・現状: Shippori Mincho を Google Fonts から読んでいる（レイアウトで 2 オリジンへ preconnect）。外部 DNS/TLS 往復が LCP に乗り、可用性も外部依存。
- 提案内容: Google Fonts の CSS と同じ unicode-range 分割の woff2 サブセット（weights 500/600）を取得して `app/assets` に置き、`@font-face` を自前 CSS 化（`font-display: swap` 維持）。preconnect 2 行を削除。「web フォントは明朝 1 本」の方針は維持される。
- 期待効果: LCP 改善（外部往復の排除）、CSP を将来有効化する際の単純化。
- Impact: Medium
- Effort: Medium
- 優先度: P2

## [improvement] Issue 32: エラーページ（404/422/500）の日本語化・ブランド化
- 種別: improvement
- 観点: H / C
- 背景・現状: `public/404.html` 等が Rails 既定の英語ページ。未注釈語や削除済み語への流入・リンク切れ時に、日本語サイトとして体験が断絶し、回遊も切れる。
- 提案内容: 3 ページを日本語・自前デザインで書き換え（静的 HTML のためトークン値はリテラルで埋め込み。`icon.svg` の作法と同じ）。404 にはホーム・単語一覧・検索への導線を置く。
- 期待効果: エラー時の離脱抑制、ブランド一貫性。
- Impact: Low
- Effort: Low
- 優先度: P2

## [feature] Issue 33: 用例（usage example）フィールドの追加
- 種別: feature
- 観点: E / B
- 背景・現状: 語義に用例・出典を持つ場所が無い。定義 + 用例が揃うと辞書ページとしての情報量・独自性が大きく上がるが、現スキーマでは表現できない。
- 提案内容: `word_sense_examples` テーブル（`word_sense_id`, `text`, `source`(任意)）を追加し、アノテーション・コンソール（`admin/annotations`）に入力欄、`words#show` に表示、JSON-LD（Issue 16）にも反映。データ入力の運用コストが掛かるため、着手前に運用方針を相談。
- 期待効果: ページの独自性・情報量の向上（他辞書との差別化）、LLM が用例ごと引用できる構造。
- Impact: Medium
- Effort: High
- 優先度: P2

## [feature] Issue 34: 統計ページ（収録データの分布・集計）
- 種別: feature
- 観点: F / G
- 背景・現状: 収録データの統計（ジャンル別語数・読み文字数の分布・語種別・品詞別・先頭文字別など）を見せるページが無い。データベースサイトの「全体像が見える」ページは回遊・被リンク獲得（「◯◇のデータによると〜」と引用される）に効く。一方で、毎回全レコードを走査する実装はスケールしないため、集計テーブルの要否とその書き込みタイミングが論点だった。
- 提案内容: **2 段階で実装する。統計テーブルは先行して作らない**（統計は元データから常に再計算できる導出データであり、後からの移行が可能なため）。
  - **Phase 1（初版・当面はこれで十分）**: `StatsController#index`（`/stats`、`allow_unauthenticated_access`）でオンライン集計（`WordSense.published` を対象に `group(...).count` 群。インデックス済みカラムのみ使用）+ `Rails.cache.fetch`（TTL 数時間、またはアノテーション保存時にキー削除）。想定規模（1 万語）では GROUP BY は数十 ms 以下で、キャッシュと併せて十分持つ。グラフ表現は `docs/design.md` 準拠（墨・朱のみ。重いチャートライブラリは入れず、CSS/インライン SVG の棒グラフ程度に留める）。
  - **Phase 2（数十万レコード級になったら）**: 集計テーブル（例 `stats_snapshots`）+ **冪等な再集計タスク `stats:rebuild`**（`backfill:reading_metrics` と同じ作法）を導入。「正 = フル再計算タスク、登録・アノテーション時のフックはキャッシュ削除 or 非同期の再集計トリガーに留める」構成とする（増分更新のみに依存すると削除・編集・手動修正でズレたとき自己修復できないため）。
- 期待効果: 回遊・再訪の増加、統計データとしての被リンク・引用の獲得、サイトの信頼性提示（収録規模の可視化）。
- Impact: Medium
- Effort: Medium（Phase 1 のみ。Phase 2 は別 PR）
- 優先度: P2（Issue 26 のキャッシュ基盤と同時期以降が効率的。データが数百語を超えてから公開する）

## 最初の2週間のロードマップ

前提はすべて確定済み（下記「前提の確定事項」参照）: ドメイン = `nagai-kotoba-database.jp`、計測 = GA4、収録基準 = 読み 10 文字以上。

**Week 1 — 公開前の土台（P0 一式 + 即効 bug）**
1. Issue 13（favicon 差し替え。即日）
2. Issue 18 → Issue 14（リード文を先に作り、meta description に流用。セットで 1〜2 PR）
3. Issue 15（sitemap + robots.txt）
4. Issue 17（ファセットのインデックス方針）
5. Issue 19（計測 + Search Console。データ投入と並行して開始し、インデックス状況を観測開始）

**Week 2 — 発見性の「面」を増やす（P0 残り + P1 前半）**
6. Issue 16（JSON-LD 3 種）
7. Issue 20（About）→ Issue 24（llms.txt。文言を共有）
8. Issue 21（/genres ハブ）
9. Issue 23（関連語セクション）
10. Issue 27（hosts 設定 + canonical ホスト 301。com → jp 移行のタイミングと合わせる）

**Week 3 以降（データ量の成長に合わせて）**: Issue 22 → 25 → 26 → 28〜34（Issue 34 の統計ページは Issue 26 のキャッシュ基盤の後が効率的）。
Issue 29（OGP 画像）はデータが数百語を超えて共有が発生し始めた段階で着手が費用対効果的に良い。

## 前提の確定事項（2026-07-06 オーナー回答）

1. **本番ドメイン**: `nagai-kotoba-database.jp` で確定。現在は旧システムが `nagai-kotoba-database.com` で稼働中。データ移行完了後に nginx で com → jp へリダイレクト予定（詳細は Issue 27。旧サイトがインデックス済みの場合は URL 単位の 301 と Search Console「アドレス変更」を行う）。
2. **アナリティクス**: GA4 で確定（Issue 19 に反映済み。Turbo 対応の計測イベント送信が必須）。
3. **収録基準**: **読み 10 文字以上**で確定。About（Issue 20）・llms.txt（Issue 24）・リード文（Issue 18）・メタ文言（Issue 14）の記述に使う。
4. **ライセンス**: 記載する方針。ただし **MIT はソフトウェア（コード）向けライセンス**のため、単語データ＝コンテンツの利用条件としては不適合。データには **CC BY 4.0（クレジット表記 = サイト名 + URL）を推奨**。リポジトリのコードを OSS 公開する場合はそちらに MIT が適合。最終確定は Issue 20（About）着手時に行う。
5. **インデックス解禁**: 未定。手元データ約 6,000 語で、アノテーションに時間を要する見込み。未注釈語は 404 のため公開面は注釈済みの語だけで構成される。**注釈済み 300〜500 語を目安に解禁**し、それまでは全ページ `noindex`（レイアウトの meta robots を環境変数等で切替）としておく運用を推奨。解禁時に noindex を外し、sitemap（Issue 15）を Search Console へ送信する。
