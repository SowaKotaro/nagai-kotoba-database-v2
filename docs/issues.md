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
