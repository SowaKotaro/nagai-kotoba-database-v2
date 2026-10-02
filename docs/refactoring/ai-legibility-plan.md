# AI 向け可読性改修の計画書（refactor/ai-legibility）

> **状態: 承認待ち（フェーズ2）**。承認されるまでコードは変更しない。
> これは改修の作業計画であり、現行仕様の正ではない（正は `CLAUDE.md`・`docs/` の各文書・コード）。
> 改修が終わったら、この文書と監査記録（[`audits/`](audits/)）は `docs/history/` へ移す（G4-05）。
>
> **2026-10-02 追記**: 進め方は [`STRATEGY.md`](STRATEGY.md)、進捗は [`LEDGER.md`](LEDGER.md) に移した。
> この文書と食い違うところ（作業ブランチ名・§0.2 の「作業中のファイル」・§8 の記録先など）は、そちらを優先する。
> この文書は段階 3（P-01）で改訂する。

## 0. 前提

### 0.1 目的

人間はコードを書かず、将来の AI エージェントが保守する。**将来のエージェントがコードを誤解せず、
最小の探索で正しい変更ができる状態**にする。評価基準は次の4つ。

1. コード・コメント・docs・命名が互いに矛盾していない（嘘の情報がない）
2. 同じ種類の処理は1つの正典パターンで書かれており、手本が一意に決まる
3. 派生値・副作用・データの出どころが、該当箇所から辿れる
4. 「どこに何があるか」を探す手数が少ない

### 0.2 この改修の制約

- 作業はブランチ `refactor/ai-legibility` だけで行う。**main への push・マージはしない**
  （main への push で `.github/workflows/deploy.yml` が本番デプロイを走らせる）。ブランチの push も指示があるまでしない。
- 外部から見える振る舞いを変えない: 公開ページの URL と HTML の意味構造、JSON API のレスポンス形式、
  og:image、収録リクエストフォーム、管理者認証。
- 適用済みの `db/migrate` は書き換えない。スキーマは変更しない（必要なものは §7 に提案として書くだけ）。
- 照合順序の規約（全体 `utf8mb4_0900_ai_ci`、読み・表層形のカラムだけ `utf8mb4_0900_as_ci`）を維持する。
- 「しずか」の方針を維持する（web フォント無し・JS 最小限・CSS フレームワーク無し・importmap のまま・ビルドツールを入れない）。
- MeCab / rsvg-convert が無い環境でも機能が止まらないフォールバックを維持する。
- gem・JS ライブラリを追加・削除しない。
- 既存テストの期待値を変えない。変える必要がある項目は実施せず、§7.3 に理由を書く。
- **所有者の作業中のファイルには触れない**。`README.md`、`.claude/commands/expand.md`、
  `.claude/skills/word-expansion-research/`（`SKILL.md` と未追跡の `reading_length.rb`）に未コミットの変更がある。
  これらに関わる項目は §7.6 に回す。コミットには `git add <パス>` で明示したファイルだけを含める。

### 0.3 合格判定（各コミットで全て満たす）

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
bin/importmap audit
bin/rails test
CHROME_BIN=<Selenium Manager が選ぶ chromedriver と同じメジャーの Chrome> bin/rails test:system
```

- 連結形の `bin/rails test test:system` はローカルでは `LoadError` になる（§1）。2本に分けて実行する。
- 失敗したら直すか、そのコミットを取り消す。満たさないまま次の項目へ進まない。
- 既知の不安定なテストが1本ある: `test/system/admin_annotation_deck_test.rb` の「提案の新設候補をその場で作ると…」は、
  変更と関係なく落ちることがある（CI では通っている）。これだけが落ちたら、再実行して再現するかを確かめる。

## 1. ベースライン（2026-09-27 計測。main = `a04f375`）

| チェック | 結果 |
|---|---|
| `bundle exec rubocop` | 310 files inspected, no offenses |
| `bundle exec brakeman --no-pager` | No warnings found |
| `bundle exec bundler-audit check --update` | No vulnerabilities found |
| `bin/importmap audit` | No vulnerable packages found |
| `bin/rails test` | 785 runs, 15300 assertions, 0 failures, 0 errors, 1 skip（rsvg-convert が無いため共有カードの描画テストが skip） |
| `bin/rails test:system`（Chrome 154） | 26 runs, 220 assertions, 0 failures, 0 errors |

アサーションの数は、同じコードでも実行のたびに数件ずれる（条件によって assert する経路があるため）。
2026-09-30 にこの計画書を足して再実行したときは 15301 件 / 218 件で、失敗は 0 だった。

計画の前提として、統合担当が実行して確かめた事実は次の2つ。

- **`bin/rails test test:system` はローカルでは `LoadError` になる**。`test:system` をファイルパスとして読むため。
  CI は `bin/rails db:test:prepare test test:system` で通っている（先頭が rake タスクなので、全体が rake タスクとして解釈される）。
- **照合順序の実測**（MySQL 8.4。docker の開発用 DB で文字列リテラル同士を比較）:

  | 比較 | `utf8mb4_0900_as_ci` | `utf8mb4_0900_ai_ci` |
  |---|---|---|
  | ハ / バ（清濁） | 区別する | 同一視する |
  | ヤ / ャ、ツ / ッ（小書き） | **同一視する** | （未計測） |
  | あ / ア（ひらがな・カタカナ） | 同一視する | （未計測） |
  | ア / ｱ（全角・半角のカナ） | 同一視する | （未計測） |
  | A / a（大文字・小文字） | 同一視する | （未計測） |
  | ー / -（長音符・ハイフン） | 区別する | （未計測） |
  | `REPLACE()` | 照合順序によらずバイナリで比較する | — |

## 2. 監査の概要

フェーズ1では、8体のサブエージェントが読み取りだけで監査した。docs は分量が多いので2体に分けた。
報告の全文は [`audits/`](audits/) にある（行番号は `a04f375` 時点のもの）。

| 領域 | ID | 件数 | 報告 |
|---|---|---:|---|
| app/models・services・jobs | M- | 21 | [audits/models.md](audits/models.md) |
| controllers・helpers・views | C- | 23 | [audits/controllers-views.md](audits/controllers-views.md) |
| app/javascript | J- | 20 | [audits/javascript.md](audits/javascript.md) |
| app/assets/stylesheets | S- | 13 | [audits/stylesheets.md](audits/stylesheets.md) |
| db・config・lib・CI | CFG- | 18 | [audits/db-config.md](audits/db-config.md) |
| test | T- | 19 | [audits/test.md](audits/test.md) |
| 案内系の文書（CLAUDE.md・overview・data-model・スキルなど） | DOC- | 16 | [audits/docs-guides.md](audits/docs-guides.md) |
| 仕様・記録系の文書と、それを参照するコメント | SPEC- | 24 | [audits/docs-specs.md](audits/docs-specs.md) |

- 監査は利用上限で2回中断し、再開したときに残りを重要な項目に絞った。確認しきれなかった範囲は、各報告の末尾の「未確認のまま残した範囲」に書かれている。
- 各指摘には確度（確認済み / 推測）が付いている。**計画に採用した推測には「要確認」と書き、フェーズ3で実測してから着手する。**
- 統合担当が実物で裏取りした主な指摘は次のとおり。
  - DOC-01（deploy.yml）、DOC-02（テストコマンド）、DOC-03（スキルの旧フロー）、DOC-04（as_ci の一覧）
  - M-01（backfill の欠落）、M-07（照合順序。§1 の実測で決着）、M-16（`unannotated` の説明）
  - SPEC-01、SPEC-02、SPEC-05、J-01、C-01
  - C-16・M-15・S-04・J-19・T-15 の未使用判定
  - §5 の集約が成り立つ前提（`WordSort` の新着順が既存の並びと同じこと、stimulus-loading が `_controller` で終わるファイルしか登録しないこと、TTL の値が一致すること）
- 不採用にした指摘は2つ。
  - M-13 のうち `WordCandidateIntake` のコメント。「1行の失敗で他の行を巻き戻さない」は実装と合っている。
  - `WordSort::RANKING_KEYS` の削除。テストが参照している。

## 3. 横断的な発見

1. **AI が最初に読む案内文書に、操作を誤らせる嘘がある**。
   - main への merge がそのまま本番デプロイになり、CI の完了を待たないことが、どこにも書かれていない。
   - 合格判定コマンドが4か所で、動かない形のまま書かれている。
   - as_ci の一覧から word_candidates が抜けている。
   - 「backfill を流せば派生値が直る」と書いてあるが、直らない列がある。
2. **派生値の組み立てが3か所に複製され、すでに1回ずれている**。
   - `ring_crossing_count` はモデルが算出するが、`backfill:reading_metrics` も `backfill:verify` も扱っていない。
   - STORED の `words.reading_density` が、after_commit で作る `max_reading_length` に依存していることも書かれていない。
3. **同じ規則の実装が複数ある**。かなの畳み込み8通り、調査 JSON の読み取り3通り、絶対 URL の組み立て10か所以上、
   代表語義の選び方2通り、管理画面の判定2通り、キャッシュの書き方3系統、しきい値の別名定数と直書き。
4. **嘘の最大の供給源は、経緯を書いたコメントが古くなったもの**。「アクセント」「朱」「太字」「印章」「検索パネル」など、
   撤去済みの設計の語彙が残っている。コメントに日付・Issue 番号・計測値を積むほど古くなる。
5. **範囲外の不具合も見つかった**（§7.1）。直すと振る舞いが変わるので、この改修では直さずに記録する。

## 4. 領域ごとの正典パターン（定義案）

改修後の CLAUDE.md（G4-01）に載せる定義の案。「段階3の後」と書いたものは、その項目が終わるまでは既存の手本を使う。

### 4.1 モデル・サービス

- **置き場所**
  - `app/models` には ActiveRecord と、それ以外の Ruby をすべて置く（値オブジェクト・クエリ／集計・書き込み処理・フォーム・調査 JSON の入出力）。
  - `app/services` には**外部プロセスを起動するラッパーだけ**を置く（手本 `share_card_renderer.rb`）。
  - `app/models/concerns` には、複数のモデルが include する振る舞いを置く。
  - サブディレクトリは作らない（定数名が変わるため）。
- **クラス冒頭の種別ラベル**は次の5語に揃える。
  - 値オブジェクト（DB に触れない）
  - クエリ・集計（読み取りとキャッシュ）
  - 書き込み処理
  - フォーム
  - 調査 JSON の入出力
- **派生値**
  - 手入力させない。次の3つのどれかで作る: SQL の STORED 生成カラム／値オブジェクト＋`before_validation`／`after_commit` で焼き直す代表値（`WordSenseMetrics`）。
  - 値オブジェクトは `self.call(input)` の純粋関数にする（手本 `last_char.rb`・`char_type_pattern.rb`）。
  - 読み由来の値の組み立ては `WordSense.reading_derivations(reading)` の1か所だけにする（段階3の後）。
  - **派生列を足したら、data-model.md §3 の表・backfill・verify を同じコミットで直す。**
- **コールバックを通らない更新**（`update_all`・`update_columns`・生 SQL）には、その場で理由をコメントし、事後の直し方（backfill）を示す。
- **集計とキャッシュ**
  - 版付きの `CACHE_KEY`・`CACHE_TTL`・`RACE_CONDITION_TTL` を持つクラスメソッドにする（手本 `site_statistics.rb`・`published_sense_counts.rb`）。
  - 無効化は TTL だけで行う（`Rails.cache.delete` は使っていない）。
- **基準値・しきい値**は、その概念の持ち主に1つだけ置く。別名の定数は作らない。
  - `WordSense::MIN_READING_LENGTH`
  - `Levenshtein::SIMILARITY_THRESHOLD`
  - 立項スコアと確信度は `AnnotationProposal`（段階3の後）
  - マスタ名は `SeedCatalog`
- **調査 JSON の入出力**
  - 取り込みの手本は `word_candidate_notation_import.rb`。`ResearchJson.array_at` で読む。入口は `call`。形が読めなければ nil を返す。外側のトランザクションに加えて行ごとに `requires_new` を張る。結果は `Struct(keyword_init: true)` で返す。
  - 書き出しの手本は `annotation_research_export.rb`。`as_json` / `to_json` に VERSION を付ける。
- **外部コマンド**（手本 `share_card_renderer.rb`）
  - 有無の判定はクラスで1回だけ行う。
  - コマンドは配列で渡す。
  - `SystemCallError` を捕まえる。
  - タイムアウトを持つ。
  - 失敗したら nil を返し、呼び出し側が既定値へフォールバックする。
- **状態**は、間隔を空けた整数の enum で表す（手本 `word_candidate.rb`）。
- **公開条件**は、語は `Word.annotated`、語義は `WordSense.published` だけを使う。語と語義で名前が違うことを word.rb に明記する。
- **かなの畳み込み**は `KanaFold`（段階3の後）、**代表語義**は `Word#primary_sense`（段階3の後）を使う。

### 4.2 コントローラ・ヘルパ・ビュー

- **認証**
  - `ApplicationController` が、全アクションを既定で認証必須にしている。
  - 公開側は `allow_unauthenticated_access only: %i[...]` で、開放するアクションを明示する（手本 `browse_controller.rb`）。
  - 管理側は `Admin::BaseController` を継承するだけでよい。
  - 未ログインの拒否は、`test/integration/admin_authentication_test.rb` が全ルートについて検証している。
- **Strong Parameters**
  - モデルに渡す属性は `params.require(:x).permit(...)` で受ける（手本 `word_candidates_controller.rb`）。
  - 複数の画面で共有する許可の集合は、定数1つにまとめる（手本 `Admin::AnnotationQueue::WORD_ATTRIBUTES`）。
- **並び順**は `WordSort` の定数だけを使う。新着順も `"created_desc"` を使う。
- **キャッシュ**
  - 集計値のキャッシュはモデル側に置く（4.1）。
  - コントローラには HTTP の宣言（`expires_in` / `stale?`）だけを書く。
  - 全件出力（sitemap・llms-full）は `PublishedWordsDigest` の版と TTL を使う（段階3の後）。
- **絶対 URL** は `SiteUrl` だけで作る（段階3の後）。
- **ヘルパとパーシャルの使い分け**
  - 値・属性・文字列を返すならヘルパ、マークアップのまとまりならパーシャル。
  - ヘルパでは DB を引かない。引く場合はメモ化し、そのことが分かる名前にする。
  - JS に渡す値と文言は、ヘルパで data ハッシュを組んで渡す（手本 `word_requests_helper.rb` の `reading_counter_data`）。
- **i18n**
  - 表示文言は `ja.yml` に置く。
  - 新しいコードでは、キーをビューのパスに合わせる。
  - 区切り記号も i18n に置く。
- **フラッシュ**は、レイアウトの `#flash` だけに出す。
- **同じ規則を名乗る2つの画面**では、その規則を concern か定数で1か所に置く（手本 `Admin::AnnotationQueue`、`WordSense::KEYWORD_MATCH_CONDITION`）。

### 4.3 JavaScript

- **冒頭コメント**には、目的・使う画面・JS が無いとどうなるか・連携するイベントを書く（手本 `decision_list_controller.js`・`row_select_controller.js`・`panel_switch_controller.js`）。
- **Ruby の値と文言**
  - ヘルパから data 属性で渡す。JS に日本語や基準値を直書きしない。
  - 文言のプレースホルダは `%{name}` にする。
- **ページ全体に掛かるイベント**は、data-action の `@window` / `@document` で受ける（手本 `shared/_header.html.erb` の nav-menu）。
  - `addEventListener` を使うのは matchMedia などに限り、disconnect で必ず外す（手本 `theme_controller.js`）。
- **開閉状態を持つ部品**は、Turbo がキャッシュする前に閉じる（手本 `nav_menu_controller.js`）。タイマーは disconnect で clear する。
- **コントローラ同士の連携**は、`this.dispatch()` と受け手の data-action で結ぶ（手本 `sense_completeness` と `_sense_fields.html.erb`）。
  - document 全体に流すイベントは `theme:change` だけにする。
- **DOM の生成**は、サーバ側のマークアップを `<template>` target に置いて複製する（手本 `nested_form_controller.js`）。
  - createElement を使うのは、クライアントだけで描く図に限る。
- **fetch** は `inline_add_controller.js` の `post()` の形にする（CSRF・セッション切れ・JSON 以外の応答を扱う）。失敗したら必ず画面に出す。
- **共有する関数**は `app/javascript/controllers/support/` に置く。stimulus-loading は `_controller` で終わるファイルしか登録しないことを確認済み。
- **localStorage** の読み書きは try/catch で包む（手本 `theme_controller.js`）。
- **段階的な強化**は、サーバが全部を描き、JS が畳む（または表示する）形にする（手本 `rankings/index.html.erb` の hideOnConnect、`candidates.css` の `data-js-only`）。
- **Plotly** は、意図して importmap にピンしない。Sprockets で配信し、UMD のグローバルとして使う。そのため `bin/importmap audit` の対象外になる。

### 4.4 CSS

- **色**は `var(--token)` だけを使う。
  - 色を足すときは、tokens.css に「ライトの値＋`--dark-*`＋2つの適用ブロック」を書く（手本 tokens.css）。
  - 管理画面の色は、admin.css の `.is-admin` の1ブロックに置く。
- **並んだ要素の間の罫**は、親を `display:grid; gap:1px; background:var(--border)` にし、子を面の色で塗って作る（手本 `.entry-list` / `.entry-row`、`.rank-list`）。
- **部品の手本**
  - 丸タグ `.tag`
  - ボタン `.btn` 系
  - エラーの枠 `.form-alert`
  - 視覚的に隠す `.visually-hidden`
  - 選択状態 `.check-chip`
  - フォーカス: base.css の `:focus-visible`
  - transition: `var(--transition)`
- **置き場所の実態**（改修ではファイルを移さず、文書に書く）
  - tokens → base → layout → components の後に、annotate・candidates・admin を読む。**管理用の CSS も全ページで読まれる**。
  - layout.css にも一部の部品（nav-menu・theme-toggle・flash・admin-nav）があり、components.css にも管理画面の部品がある。
  - 読み込み順に依存する規則には、両側に注記する。
- **直書きしてよい範囲**（tokens.css の冒頭に書く）
  - 色は必ずトークンを使う。
  - 余白は、区画のリズムにはトークンを使い、部品の中の微調整の px は直書きしてよい。
  - 級数・行間は直書きしてよい（級数の正は design.md §2）。

### 4.5 DB・設定・タスク

- **読み・表層形のカラム**には `collation: "utf8mb4_0900_as_ci"` を明示し、理由を一言コメントする（手本 `db/migrate/20260924100000_create_word_candidates.rb`）。
  as_ci が何を同一視するかは data-model.md §6 に書く（§1 の実測）。
- **マスタ名**は `SeedCatalog` を唯一の正とする。コードで名前を使うときはカタログの定数を参照し、テストで固定する（手本 `test/models/linguistic_feature_glossary_test.rb`）。
- **アプリのスイッチ（環境変数）**は `config/application.rb` で1回だけ読み、`config.x` に置く（手本は同ファイルの REQUESTS_ENABLED）。
- **rake タスク**
  - 規則はモデルに任せる。
  - desc に、触る列をすべて書く。
  - 冪等にする。
  - トップレベルで `def` しない。
- **デプロイ**
  - main への push で deploy.yml が `cap production deploy` を実行する。CI の完了は待たない。
  - seed は `deploy:migrate` の直後に毎回走る。

### 4.6 テスト

- **どの層で書くか**
  - 変換・判定の規則は、値オブジェクトとモデルのテストで書く。
  - 画面の出し分け・リンク・フォームの項目名は、結合テスト（assert_select）で書く。
  - system テストは、実ブラウザ（JS の実行・レイアウトの計算）が要る挙動だけに書く。
- **管理画面のテスト**は `setup { sign_in_as(admins(:one)) }` でログインする（手本 `test/controllers/admin/candidates/lists_controller_test.rb`）。未ログインの検証は各テストに書かない。
- **テストデータ**
  - 基本はフィクスチャを使う。
  - 場面ごとに要る公開語は `create_published_word` で作る（`mark_annotated` を使う。段階3の後。今の手本は `test/integration/words_feed_test.rb`）。
  - `create!` に派生値を渡さない（保存時に上書きされる）。
- **外部に出る形式**は、キーの集合ごと固定する（段階0の後の `words_api_test.rb`）。
- **時刻**は `travel_to` で固定する。
- **キャッシュ**（段階3で test_helper に集約する）
  - フラグメントキャッシュは `with_fragment_cache`（`ActionController::Base.cache_store` を差し替える）。
  - `Rails.cache.fetch` は `with_rails_cache`。
- **設定と ENV** は、元の値に戻す `with_config` / `with_env` を使う（段階3で test_helper に集約する）。
- **外部コマンド**
  - 依存するテストは、サービスの `available?` を見て skip する。
  - フォールバックは、`available?` を false にスタブして確かめる。
  - 手本は `test/services/share_card_renderer_test.rb`、`test/controllers/words/share_cards_controller_test.rb`。
- **system テストの操作**
  - JS の接続は `wait_for_stimulus` で待つ。
  - 押し直しても結果が同じ操作は `click_expecting` を使う。
  - 押し直すと困る操作は `click_via_js` を使う。
  - turbo_confirm は `click_accepting_confirm` を使う。
- **canonical ホスト**は、test_helper の定数1つにまとめる（段階3の後）。

### 4.7 文書とコメント

- **事実ごとに正を1か所だけ置き、他の文書からはリンクするだけにする**。

  | 事実 | 正 |
  |---|---|
  | カラム定義 | `db/schema.rb` |
  | 照合順序（何を同一視するか・as_ci の対象） | data-model.md §6 |
  | 派生値（作る場所・再生成・verify） | data-model.md §3 の表 |
  | 合格判定コマンド | CLAUDE.md |
  | デプロイと CI | overview.md（運用の章。G4-03 で新設） |
  | 環境変数 | overview.md §8 |
  | デザインの値と禁止事項 | design.md |
  | 調査の流れ（スキル → 管理画面） | research/README.md |
  | 調査 JSON の形式 | 各 SKILL.md と schema.json |
  | マスタ名（ジャンルなど） | `SeedCatalog`（genres.md はその写し） |
  | 収録基準 | 方針は annotation-guidelines.md §0、値は `WordSense::MIN_READING_LENGTH` |
  | 立項スコア | annotation-guidelines.md §2 |
  | ルート | `config/routes.rb`（画面の役割は overview.md §5） |

- **コメントの扱い**
  - 残すもの: なぜそうしているか、不変条件、外部との約束、長いファイルの区画見出し。
  - 削るもの: 直後のコードを言い換えただけのコメント。
  - 移すもの: 経緯（日付・Issue 番号・計測値・試作の記録）は docs/history か changelog へ移す。
- **参照の書き方**
  - 行番号ではなく、シンボル名と「文書名＋節」で参照する（行番号は必ずずれる）。
  - 件数（「13 条件」など）は文書に書かず、出どころを指す。

## 5. 改修項目

リスクの目安:
- **低**: 振る舞いに触れない（文書・コメント、参照の無いコードの削除、テストの追加）。
- **中**: 構造は変えるが、出力は同一（特性テストで固定してから行う）。
- **高**: 本番の運用・設定に関わる。この計画には入れていない。

### 段階0: 特性テストの追加（テストだけを足す。アプリのコードは変えない）

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| T0-01 | 公開 JSON API のキー集合と入れ子を固定する。対象は詳細・一覧・license。ジャンルの無い語義で `genre` が null になること、`variants` の形も固定する | JSON に触れる集約（C3-16・C3-17）の安全網になる | test/integration/words_api_test.rb | 低 | — | T-01 |
| T0-02 | 外部コマンドのフォールバックを固定する。共有カードは、`fetch` が nil のときと描けない語のときに既定カードへ回る。MeCab が無いとき、ReadingExtractor は nil の配列、MorphemeExtractor は空配列を返す。setup の skip に掛からない別のクラスに書く | 「無くても止まらない」の担保。C3-04 の前提 | test/controllers/words/share_cards_controller_test.rb、test/services/reading_extractor_test.rb、test/services/morpheme_extractor_test.rb | 低 | — | T-03 |
| T0-03 | 収録リクエストのうち、まだ固定されていない振る舞いを固定する。受付停止中に `/`・`/words`・`/about` から導線が消えること、トークンの期限切れで 422 になること、フォームの項目名 | 公開面で唯一の書き込み経路を守る | test/controllers/word_requests_controller_test.rb | 低 | — | T-04 |
| T0-04 | 公開ページのうち、まだ固定されていない振る舞いを固定する。今日の一語、ホーム検索の `q`、sitemap の `<loc>` の集合、Atom（件数の上限・絞り込みを無視すること・canonical の URL）、ログイン後に元の URL へ戻ること | C3-18 の安全網。公開クエリ名 `q` を守る | test/controllers/home_controller_test.rb、sitemaps_controller_test.rb、sessions_controller_test.rb、test/integration/words_feed_test.rb | 低 | — | T-05 |
| T0-05 | 多語義語の代表語義と語義の順序を固定する。先頭の語義が最長でない語を使い、ホームの看板・一覧の行・詳細の語義順・JSON の `senses` の順を確かめる | C3-14 の安全網 | words_controller_test.rb、home_controller_test.rb、words_api_test.rb | 低 | — | M-11、C-02 |
| T0-06 | 照合順序の帰結を固定する。表層形の一意制約は、かなの種類・小書きの違いを同一視し、清濁は区別する。`char_type_pattern`（ai_ci）を大小を区別せずに検索すると、あとアを同一視する | D1-03 で文書に書く事実を、テストが担保する | test/models/word_test.rb、word_sense_search_test.rb | 低 | — | CFG-04、M-07 |
| T0-07 | `body.is-admin` の付き方を固定する（管理画面では付き、公開ページとログイン画面では付かない） | C3-06 の安全網 | test/integration/（新規） | 低 | — | S-09、C-18 |
| T0-08 | 検索スライダー（range_slider）の表示文言と hidden の値を固定する（system テスト） | C3-20 の安全網 | test/system/（新規） | 中（system テストは不安定になりやすい） | — | J-07 |
| T0-09 | tokens.css のダークの2ブロック（`@media` と `[data-theme]`）が一致していることと、application.css の読み込み順を静的に確かめる | トークンの足し忘れを検出する。C3-21 の安全網 | test/assets/design_tokens_test.rb | 低 | — | S-08、S-02 |
| T0-10 | 提案の取り込みが、トップレベルの `linguistic_features` を捨てることを固定する | C3-02 の安全網 | test/models/annotation_proposal_import_test.rb | 低 | — | M-05 |
| T0-11 | `backfill:sense_metrics` が、崩した代表値を元に戻すことを固定する | C3-12 の安全網 | test/tasks/backfill_task_test.rb | 低 | — | T-06、CFG-02 |
| T0-12 | 名前と中身がずれているテストを直す。テスト名を中身に合わせ、名前が約束していた検証は新しいテストとして足す（単語を消すと特徴も消える、同じ該当部分の特徴を別の語義に付けられる）。既存の assert は変えない | テスト名を信じた誤認を防ぐ | test/controllers/admin/words_controller_test.rb、test/models/word_sense_feature_test.rb、reannotation_export_test.rb | 低 | — | T-12 |

### 段階1: 文書・コメントの矛盾解消（嘘を消す。振る舞いは変えない）

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| D1-01 | **デプロイと CI の実態を書く**。<br>・main への merge（push）で deploy.yml が本番へ自動デプロイし、CI の完了を待たない。<br>・seed は `deploy:migrate` の直後に毎回走り、マスタの改名（`*_RENAMES`）も行う。<br>・本番の DB 接続はサーバ上の database.yml が持つ（リポジトリの production ブロックと deploy.rb の `default_env` は使われていない）。<br>書く場所: CLAUDE.md（厳守事項に1行）、overview.md の §2 と §8、cppmtm.md の merge 手順への注記、config/deploy.rb の desc、使われていない設定へのコメント、deploy.yml の冒頭のコメント（インフラ設定のファイルだが、変えるのはコメントだけ） | エージェントが merge の重さを誤解しなくなる | CLAUDE.md、docs/overview.md、.claude/commands/cppmtm.md、config/deploy.rb、config/database.yml、.github/workflows/deploy.yml | 低 | — | DOC-01、CFG-01、CFG-05 |
| D1-02 | **合格判定コマンドを、動く形に直す**。<br>・CLAUDE.md・overview §9・cppmtm.md を、`bin/rails test` と `bin/rails test:system` の2本（または CI と同じ `bin/rails db:test:prepare test test:system`）にする。<br>・WSL で要る環境変数の名前（CHROME_BIN、必要なら LD_LIBRARY_PATH）を書く。<br>・eager load は CI=1 のときだけ効くことを書く。<br>・「ローカルで通れば CI も通る」を訂正する。 | 最初の一手で「テストが壊れている」と誤診しなくなる | CLAUDE.md、docs/overview.md、.claude/commands/cppmtm.md | 低 | — | DOC-02、CFG-09 |
| D1-03 | **照合順序の記述を、§1 の実測に合わせる**。<br>・CLAUDE.md の as_ci 一覧には word_candidates が無い。一覧は data-model §6 だけに置き、CLAUDE.md からは参照するだけにする。<br>・data-model §6 に次を足す: 小書き・全角と半角も同一視されること、一意制約にも同じ同一視が効くこと、`word_sense_features.target` / `target_reading` は ai_ci のままであること、`char_type_pattern` は ai_ci であること、マスタ名の一意制約は ai_ci であること（清濁だけが違う名前は作れない）。<br>・word_sense_metrics.rb と data-model §5 にある「清濁が畳まれて」を訂正する。<br>・`char_type_pattern_matching` のコメントに「あ＝ア」を補う。 | 照合順序を「直す」誤った変更を防ぐ | CLAUDE.md、docs/data-model.md、app/models/word_sense_metrics.rb、app/models/word_sense.rb | 低 | T0-06（テストは後でもよい。事実は §1 で実測済み） | DOC-04、CFG-03、CFG-04、M-07、M-16 |
| D1-04 | **派生値の一覧と直し方を、1つの表にまとめる**。<br>・data-model §3 に「カラム／作る場所／再生成するタスク／verify の対象か／依存する派生値」の表を置き、CLAUDE.md からは参照するだけにする。<br>・STORED の reading_density が max_reading_length に依存することを明記する。<br>・**C3-12 と同じコミット群で行う**（backfill の対象が変わるため）。 | 派生値の出どころを1か所で辿れる | docs/data-model.md、CLAUDE.md | 低 | C3-12 と同時 | DOC-05、M-02、CFG-02 |
| D1-05 | **CLAUDE.md の規約文を、差分を最小にして実態に合わせる**（全体の再編は G4-01 で行う）。<br>・認証: 全アクションが既定で認証必須で、公開側は `allow_unauthenticated_access` で外す。「書き込み系に before_action を付ける」は実態と違う。<br>・ジョブ: 1本も無い。重い処理（共有カード・代表値の UPDATE・MeCab）は意図して同期で実行している。<br>・system テスト: 「JS が無いと成立しない挙動だけ」を「実ブラウザが要る挙動だけ」に直す。<br>・管理画面の未ログイン拒否は、admin_authentication_test がまとめて検証していることを書く。 | 不要な before_action の追加や、共有カードの非同期化といった「規約どおりの改悪」を防ぐ | CLAUDE.md | 低 | — | DOC-09、T-10、T-02 |
| D1-06 | **調査スキルと調査手順の「この後の流れ」を、現行のフローに合わせる**。<br>・収穫・表記・読みの各スキルは、「上部リストをそのまま notation.txt へ」「重複は登録 step3 が弾く」という旧フローを案内している。<br>・流れの単一の出典を research/README.md にし、各 SKILL からは参照するだけにする。<br>・annotation SKILL が参照する公開 API のホストを www なしにする。<br>・annotation-guidelines の「運用」の節を直す。<br>・ja.yml の取り込み欄のプレースホルダ（旧形式）を senses 形式にする。<br>・annotation SKILL を直したら、claude.ai 用のスキル束の再生成（tools/claude-ai-skill/build.sh）と再アップロードが要る（オーナーの作業）。<br>・word-expansion-research は所有者の作業中なので除外する（§7.6）。 | ID が落ちて取り込みで全件が見送られる事故を防ぐ | .claude/skills/word-{harvest,notation,reading,annotation}-research/SKILL.md、research/README.md、docs/annotation-guidelines.md、config/locales/ja.yml | 低 | — | DOC-03、DOC-10、DOC-14 |
| D1-07 | **文書間の参照切れと、置き場所の食い違いを直す**。<br>・CLAUDE.md の「issues.md Issue 80・81」と data-model の「Issue 56」の参照先を changelog.md に直す。<br>・issues.md の docs/improvements.md（一度もコミットされていない）に注記する。<br>・issues.md の行番号による参照（word_sense.rb:251-258）をシンボル名にする。<br>・issues.md の importmap の pin についての記述を直す。<br>・overview の「完了記録は issues.md」を changelog.md に直す。<br>・changelog に #162〜#164 を追記する。<br>・.gitignore のスキル名の列挙を直す。 | 案内に従って辿ると行き止まりになる箇所を無くす | CLAUDE.md、docs/data-model.md、docs/issues.md、docs/overview.md、docs/changelog.md、.gitignore | 低 | — | SPEC-14、DOC-15、CFG-11、SPEC-12、DOC-16 |
| D1-08 | **否決・失効した判断を今も指示している記述を直す**。<br>・growth-strategy の優先順位: 特徴の遡及付与は確定事項37で却下、Bing は確定事項33で当面触らない。<br>・issues.md の確定事項16・18（朱・墨）に、失効したことを注記する。<br>・performance-report の冒頭に「§8 の現状は issues.md」と書く。<br>・stats.md の「最頻のみ --chart」を直す。<br>・「fragment cache」を「集計キャッシュ」にする。<br>・growth-strategy の「文言は home.index.* から派生」の誤りを直す。 | 却下された作業に着手するのを防ぐ | docs/growth-strategy.md、docs/issues.md、docs/performance-report.md、docs/stats.md、docs/changelog.md | 低 | — | SPEC-01、SPEC-10、SPEC-11、SPEC-16、SPEC-21、SPEC-23 |
| D1-09 | **design.md（と CLAUDE.md のデザイン節）を、CSS の実態に合わせる**。実装（後から実測して決めた値）を正とし、見た目は変えない。直す記述:<br>・ゼロ埋めの例外（一覧の目盛り `.entry-range` の 001–100 だけ）<br>・`--bg` の実際の用途と面の段<br>・章の罫は `.sheet` を含めて5箇所<br>・管理画面は、トークンに加えて一部のコンポーネントも上書きし、管理用の2色（`--admin-accent` / `--admin-warn`）を持つ<br>・行間 1.75、見出し 24px（/search だけ 21px）、ヒーロー 26px、10px の例外<br>・区切り線と囲い（sense-card / rank-board）の記述<br>・§5.3 の中の矛盾（行に角丸を持たせない／当たり判定の角丸）<br>・動きの例外（状態の変化に伴う transition と状態ラベル）<br>・検索条件の数（「13」と書かれているが、Issue 92 で区画が増えている。数は書かずに出どころを指す）<br>・Issue 84 と実測値についての古い記述<br>・管理画面はダークに対応していないという事実（§7.5） | 同じ文書のどの節を正とするかで、変更の向きが逆になる事態を防ぐ | docs/design.md、CLAUDE.md | 低 | — | SPEC-02〜06、S-13、J-12、DOC-08、S-01 |
| D1-10 | **stats.md を実装に合わせる**。<br>・図のリンク先は /words（/search ではない）。<br>・紙面の順序を直す。<br>・章題に画面の見出し（ja.yml のキー）を併記する。<br>・未実装のキャプションを直す。<br>・文書の節番号と紙面の章番号が衝突しているので、節を別の記号にする。コメントからは文書名付きで参照する。 | noindex の URL を増やす誤りを防ぐ。画面の文言から節に辿れるようにする | docs/stats.md、app/helpers/stats_helper.rb、app/assets/stylesheets/components.css（参照コメント） | 低 | — | SPEC-09、SPEC-17 |
| D1-11 | **genres.md と SeedCatalog の関係を直す**。<br>・正は SeedCatalog で、genres.md はその写し（Issue 85 で生成物にする予定）。<br>・seed_catalog.rb の「出典: docs/genres.md」と、存在しない RENAMES という定数名を直す。<br>・genres.md に書かれた小分類の追加経路を直す。タグ管理では追加できず、実際の経路はピッカー・一括注釈・提案の新設候補の3つ。 | genres.md を先に直して seed に反映されない、という逆向きの変更を防ぐ | docs/genres.md、app/models/seed_catalog.rb | 低 | — | DOC-06、SPEC-08 |
| D1-12 | **モデル・サービスのコメントを実装に合わせる**。<br>・`Word.unannotated` の説明を「注釈済み」から「未注釈」に直す。<br>・word.rb の「annotated / published スコープ」（Word には published が無い）。語と語義で公開条件の名前が違うことを書く。<br>・ProposalApplication の「保存しない」（`persist: true` のときは中間表に書く）。<br>・WordRequestDuplicateCheck の far_apart?。<br>・KanaRow の用途（ring_crossing_count に波及する）。<br>・SiteStatistics の冒頭と「タグクラウド」。<br>・語種名（和語／漢語。正しくは「日本語」）。<br>・bulk_word_registration の「将来の差し込み口」。<br>・word_sense_metrics.rb の「テストと backfill から参照」。<br>・`WordCandidate::DECISIONS` への参照を `WordCandidateReview::CHOICES` にする。<br>・クラス冒頭の種別ラベルを 4.1 の語彙に揃える。<br>・重複チェックの3実装の違いが意図であることを書く。<br>・テストからしか使わないメソッドに「テスト用」と注記する。 | 名前やコメントから逆の意味を読み取る誤りを防ぐ | app/models の該当ファイル | 低 | — | M-03、M-06、M-15、M-16、C-12、SPEC-15、SPEC-16、DOC-16、CFG-07 |
| D1-13 | **暗黙の前提をコードに書く**。<br>・update_all でタグを統合する経路（genre / entity_type / part_of_speech）と annotations_controller の update_all は、touch と after_commit を通らない。<br>・RefreshesWordMetrics は全ての commit で発火し、冪等である。<br>・WordCandidateExpansionImport は、トランザクション内で RecordNotUnique を捕まえて続行している（MySQL に依存）。<br>・JAPANESE_ORIGIN_NAME は SeedCatalog の語種名に依存している。<br>・プロセス内のメモは再起動まで有効（glossary、形態素頻度、ShareCardRenderer.available?）。<br>・収録基準はモデルでは検証せず、登録時の UI で当てている。<br>・Candidates::BaseController#run_import の前提。<br>・公開状態を annotated_at と annotation_status の2列で持っている。 | 変更の影響範囲をコードから辿れる | app/models・app/controllers の該当ファイル | 低 | — | M-08、M-13、M-18、M-20、M-21、SPEC-13、CFG-07 |
| D1-14 | **コントローラ・ビュー・ヘルパのコメントを実装に合わせる**。<br>・home_controller の「words#feed」「新着より上」。<br>・home/index の重複コメント、words/index のファセット一覧。<br>・genres/index の「ホームと同じ定義」（実際は3通り。§7.5）。<br>・「単語一覧は public でキャッシュ」（public なのは詳細と Atom）。<br>・「太字」「アクセント」「印章」のコメント。<br>・stats_helper の「2周期」、_sound_matrix の「10×11」、_entry_row の組み方、words/show が参照する design.md の § 番号。<br>・searches_controller の許可パラメータ（words_controller と集合が違うことを明記する。§7.1）。<br>・レイアウトは CSP が未設定であることを前提にしている。<br>・テーマの復元処理2か所に、相互参照を書く。<br>・theme-color の既定値についてのコメント。 | 古い設計の語彙で誤読するのを防ぐ | app/controllers・app/views・app/helpers の該当ファイル | 低 | — | SPEC-15、SPEC-07、C-23、C-01、C-03、J-11、S-08、C-22 |
| D1-15 | **JavaScript のコメントを実装に合わせる**。<br>・importmap.rb と controllers/index.js の「公開ページではコントローラを使わない」（ヘッダーの3本は全ページで使う）。<br>・nav_drawer の「検索パネル」、char_type のキーの数、auto_submit の「親フォーム」、check_all の用途、queue_nav が先頭へスクロールすること。<br>・range_slider・feature_range の「アクセント」。<br>・genre_sunburst の「色は JS に持たせない」と直書きのパレットの矛盾、`--bg` を地と呼んでいる箇所。<br>・controllers/application.js の window.Stimulus はシステムテストに要ること。<br>・sense_cloner は Rails の nested attributes の名前に依存していること。<br>・js-genre-* はテスト用のフックであること。<br>・サーバ側の規則を JS も持っている箇所（どちらが正か）。<br>・Plotly を意図してピンしないこと。 | 「公開側は JS 無し」などの誤読を防ぐ | config/importmap.rb、app/javascript/controllers の該当ファイル、app/assets/config/manifest.js | 低 | — | J-01、J-06、J-08、J-09、J-16、J-18、J-19、J-20、CFG-10 |
| D1-16 | **CSS のコメントを実装に合わせる**。<br>・tokens.css の冒頭を 4.4 の方針にし、「画像帯」「構造は余白で作る」を直す。<br>・base.css の対象（`.mono` を含む）と「ヘッダー(--bg)」。<br>・application.css の冒頭に実際の配置を書く（candidates.css の役割、管理用の CSS も全ページで読まれること、読み込み順の意味）。<br>・components.css の古いコメント（「唯一」「4 箇所」「001–050」など。SPEC-15・S-12 に列挙）。<br>・admin.css の冒頭の方針と実測値。<br>・annotate.css の「青一色」「枠を緑に」、layout.css の「縦の基準線」。<br>・i18n の中にあるクラス名（shiritori__char・cand-export__num）の使用元。<br>・読み込み順に依存する規則の両側に注記する。 | 置き場所と方針を誤読するのを防ぐ | app/assets/stylesheets の全ファイル | 低 | — | S-02、S-03、S-07、S-10、S-12、SPEC-03〜05、SPEC-15 |
| D1-17 | **設定・タスク・テストのコメントを実装に合わせる**。<br>・application.rb の INDEXING_ENABLED（解禁済み。値は見ず、設定されているかどうかで決まる）。<br>・puma.rb に理由を書く（preload_app! の分岐、ソケットのパスと deploy_to、worker_timeout）。<br>・routes.rb に公開と管理の見出しを付け、公開 URL とクエリ名は変えないことを書く。apply_research も説明に加える。<br>・stats.rake の「本番に MeCab が無い」前提を overview の外部コマンドの表へ移す。backfill.rake の冒頭を直す。<br>・db/migrate のコメントは当時の記録で、現行の正は schema.rb であることを data-model に1段落書く。<br>・テスト側:<br>　- application_system_test_case の Google Fonts と「sticky ヘッダー」<br>　- backfill_task_test の「ずれは検出される」<br>　- 管理画面のテストに残る空の見出し5つと、word_requests テストのファイル説明<br>　- fixtures/word_senses.yml の murder の読みがひらがなである意図<br>　- システムテストの入力手段についての、互いに矛盾するコメント（**要確認**: 実行して現状を確かめてから、1か所にまとめて書く）<br>　- morpheme_frequencies_test の失敗メッセージの「朱」 | 環境や設定についての誤った知識が引き継がれるのを防ぐ | config/application.rb、config/puma.rb、config/routes.rb、lib/tasks/*.rake、docs/data-model.md、docs/overview.md、test の該当ファイル | 低 | — | CFG-08、CFG-15〜18、DOC-13、DOC-16、T-02、T-06、T-09、T-19、J-18、SPEC-16 |

### 段階2: 残骸の削除

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| R2-01 | 使われていない Ruby コードを消す。<br>・`app/helpers/articles_helper.rb`（scaffold の残り）<br>・`BulkWordRegistration::MergedEntry#match?` / `#differ?`<br>・`WordCandidate::DECISIONS`（コメントからしか参照されていない）<br>・`test/test_helpers/session_test_helper.rb` の `sign_out`<br>テストからしか使われていないメソッドは消さず、注記する（D1-12） | 存在しない機能（Article など）を推測させない | 上記のファイル | 低 | —（参照が無いことを検索で確認済み） | C-16、M-15、T-15 |
| R2-02 | 使われていないビューと i18n を消す。<br>・`shared/icons/_crown`・`_sparkle`<br>・ja.yml の `admin.annotations.nav` / `today`<br>・en.yml の `hello` | 使える部品に見える残骸を無くす | app/views/shared/icons、config/locales | 低 | —（参照が無いことを確認済み） | C-16、CFG-12、DOC-16 |
| R2-03 | 使われていない JS を消す。<br>・inline_add の `escapeHtml` の export を外す（同じファイルの中でしか使っていない）<br>・`_feature_fields` の `.js-feature` クラス | 他から使われていると誤読させない | inline_add_controller.js、admin/annotations/_feature_fields.html.erb | 低 | — | J-19 |
| R2-04 | 使われていない CSS セレクタと、効いていない宣言を消す。<br>・確認済みの8セレクタ: `.btn--danger`・`.field--keyword`・`.icon--lg`・`.reading-column`・`.search-switch`・`.tag--static`・`.word-sense-fields`・`.word-sense-feature-fields`<br>・`.is-admin .proposal`、`.admin-status-tabs .is-current`、`.page-eyebrow .icon`、`.stats-grid__item dt .icon`（**要確認**）<br>・孤立したコメント<br>・効いていない宣言: admin.css の box-shadow:none の規則、`.ann-sense.is-complete` の border-color、打ち消す相手の無い `border-bottom:0`、同じ規則の中で打ち消される `margin-left:auto`、基本と同じ値の繰り返し、直後に上書きされる `border:none`、通常時と同じ色の hover<br>・`.stats-grid` の効いていない margin、components.css の管理表の色（admin.css が常に上書きしている）<br>・未使用のトークン `--shadow-soft` | 削除済みの部品が使える部品に見える状態を無くす | admin.css、annotate.css、candidates.css、components.css、layout.css、tokens.css、docs/design.md（`--shadow-soft` への言及） | 低 | 削除の前後で、代表ページの computed style を一時スクリプトで比べる | S-03、S-04、S-05、S-07 |
| R2-05 | 設定とタスクの残骸を片付ける。<br>・`config/deploy/staging.rb`（全行がコメント）<br>・Capfile の、存在しないディレクトリへの glob<br>・Rails の雛形の英語コメント（routes.rb の末尾、db/seeds.rb の冒頭、deploy.rb の例示）<br>・stats.rake がトップレベルで `def` しているのをラムダにする | 使っていない設定を、使っているように見せない | config/deploy/staging.rb、Capfile、config/routes.rb、db/seeds.rb、config/deploy.rb、lib/tasks/stats.rake | 低（デプロイの設定だが、本番のデプロイ経路は変わらない） | — | CFG-14、CFG-17 |
| R2-06 | テストの残骸を片付ける（期待値は変えない）。<br>・stats_vowel_graph_test の効果の無い `Rails.cache.delete`（test 環境は null_store）<br>・`create!` に渡している派生値の引数（保存時に上書きされるうえ、値も誤っている） | 「create! にも派生値を渡すもの」という誤解を防ぐ | test/system/stats_vowel_graph_test.rb、test/models/word_request_duplicate_check_test.rb、test/helpers/words_helper_test.rb | 低 | — | T-07、T-11 |

### 段階3: 正典への集約（振る舞いを変えない）

リスクの低いものを先に並べている。各項目の前に、その行の「先に必要な特性テスト」がそろっていることを確かめる。

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| C3-01 | **基準値・しきい値・マジックナンバーを、その概念の持ち主に寄せる**。<br>・BulkWordRegistration の別名定数（MIN_READING_LENGTH・SIMILARITY_THRESHOLD）をやめ、持ち主の定数を直接参照する。<br>・立項スコアの境界（`<= 3` / `>= 4`）・範囲（1..5）・確信度の値を AnnotationProposal の定数にする。<br>・JAPANESE_ORIGIN_NAME を SeedCatalog の定数から参照し、「カタログに含まれる」ことを確かめるテストを足す。<br>・site_statistics の文字種の記号を、CharTypePattern の定数から組み立てる。<br>・genres/index の横棒の長さの計算を、RadialChart の比率から求める（同じ式）。<br>・収録リクエストの重複チェックのレート上限を定数にし、テストもそれを参照する。<br>・ホームの RANKING_LIMIT（10）と、ビューの `take(5)` の食い違いを直す（**要確認**: 6件目以降を使う箇所が無いこと）。<br>・ja.yml の「10文字」は、ルールそのものを述べる管理画面の説明文だけを `%{min}` で補間する。公開側の紹介文には「MIN_READING_LENGTH と一致させる」と YAML に注記する。 | 基準を変えるときに直す場所が1つになる | app/models（bulk_word_registration・annotation_proposal・bulk_proposal_approval・word_candidate・word_candidate_notation_import・word_sense・site_statistics）、app/controllers（home・word_requests）、app/views（admin/words/duplicates・genres/index・home/index）、config/locales/ja.yml、該当テスト | 低〜中 | 既存の word_request_form_test・annotation_proposal_test・bulk_proposal_approval_test。変更の前後で該当ページの HTML を比べる | M-10、SPEC-18、SPEC-13、SPEC-20、CFG-07、C-17、M-17、T-04 |
| C3-02 | **提案 payload のキーの一覧を1か所にまとめる**。<br>・AnnotationProposal に SENSE_KEYS / META_KEYS / PAYLOAD_KEYS を置き、AnnotationProposalImport・`legacy_sense_hash`・ReannotationExport から参照する。<br>・トップレベルの `linguistic_features` を保持しないことを、コメントで表明する。 | キーを足すときに直す場所が1つになる | annotation_proposal.rb、annotation_proposal_import.rb、reannotation_export.rb | 低 | T0-10 | M-05 |
| C3-03 | **一括登録での調査 JSON の読み取りを、ResearchJson.array_at に寄せる**。<br>・Hash でない要素の扱いが揃うので、現状を特性テストで確かめてから置き換える。<br>・AnnotationProposalImport はフェンス付きの JSON を受け付けるようになり、受理範囲が変わるため対象外とする（§7.1）。その旨をコメントに書く。 | 取り込みの手本が1つになる | app/models/bulk_word_registration.rb、annotation_proposal_import.rb（コメントのみ） | 低 | bulk_word_registration_test に、形が不正な入力の現状を追加する | M-12、DOC-10 |
| C3-04 | **外部コマンドの有無の判定を、クラスで1回に揃える**。<br>・ReadingExtractor（呼び出しのたびに `mecab --version` を起動している）と MorphemeExtractor を、ShareCardRenderer の形（クラスでメモし、`available?` を公開する）にする。<br>・テストの skip も、サービスの `available?` を見る形に揃える。<br>・MeCab の呼び出しにタイムアウトを足すのは、振る舞いが変わるので対象外とする（§7.1）。 | 外部コマンドの手本が1つになる | app/services/reading_extractor.rb、morpheme_extractor.rb、test/services の該当ファイル | 低 | T0-02 | M-14、T-16 |
| C3-05 | **認証の開放を明示し、小さな曖昧さを取り除く**。<br>・WordRequestsController の `allow_unauthenticated_access` に `only:` を付け、全アクションを列挙する（ルートを確認し、挙動は同じ）。<br>・words_helper で、リクエストの `params` を隠している局所変数の名前を変える。 | 公開側の開放範囲がコードから読める | app/controllers/word_requests_controller.rb、app/helpers/words_helper.rb | 低 | 既存のテスト | C-15、C-22 |
| C3-06 | **管理画面の判定を `admin_page?` の1つにする**。いまは、パスの前方一致とコントローラの型の2通りで判定している。layout の body のクラス・ヘッダーの現在地・共通ナビを、すべてこれに揃える | admin.css が効くかどうかと、管理ナビの表示が、同じ規則で決まるようになる | app/views/layouts/application.html.erb、shared/_header.html.erb、app/helpers/admin_helper.rb | 低 | T0-07 | S-09、C-18 |
| C3-07 | **管理画面で重複している UI を1つにする**。<br>・アノテーション・キューの絞り込み UI（コンソールとデッキに複製されている）を、パーシャルと、Admin::AnnotationQueue の定数・ヘルパにする。<br>・登録予定単語の状態ラベルを、ヘルパ経由に統一する。<br>・管理一覧の状態タブを STATUS_FILTERS から組み立てる。 | 同じ UI を片方だけ直す事故を防ぐ | app/views/admin/annotations・annotation_decks、app/controllers/admin/candidates、admin/words/index、app/helpers/word_candidates_helper.rb | 低 | 既存の管理画面のテスト。描画した HTML を前後で比べる | C-13、C-14 |
| C3-08 | **ページネーションの計算を値オブジェクトにする**。3つのコントローラにある同じ計算を Pagination にまとめる。マークアップの統合は §7.7 | 計算の手本が1つになる | words_controller.rb、admin/words_controller.rb、admin/word_requests_controller.rb | 低 | 公開一覧のページ送り（seed の引き継ぎ・nofollow）を先に固定する | C-09 |
| C3-09 | **50音表の定義をモデルへ移す**。SearchesHelper::KANA_COLUMNS を、行の定義を持つ KanaRow へ移す。ヒートマップの描画の統合は §7.7 | 表の定義の持ち主が一意になる | app/helpers/searches_helper.rb、app/models/kana_row.rb、3つのビュー | 低 | 既存の browse・stats・search のテスト | C-10 |
| C3-10 | **キャッシュの書き方を正典に寄せる**。<br>・sitemap・llms-full の「1日」を PublishedWordsDigest の TTL 定数にする（2つはすでに同じ値）。<br>・ホームの集計キャッシュの、リテラルで書いたキーを定数にする。<br>・「今月の新収録」の式（home_controller と site_statistics にある同じ式）を1か所にする。<br>・TTL の値は変えない。 | 同じ種類のキャッシュを足すときの手本が1つになる | app/controllers（home・sitemaps・llms）、concerns/published_words_digest.rb、app/models/site_statistics.rb | 低〜中（キーが変わるので、切り替えた直後に1回だけ作り直しが走る） | 既存の published_words_digest_test など | C-04、C-08、M-17、M-18 |
| C3-11 | **テストの書き方を正典に寄せる**（期待値は変えない）。<br>・test_helper に with_rails_cache / with_fragment_cache / with_config（元の値に戻す）/ with_env / CANONICAL_HOST 定数 / create_published_word を置き、各ファイルの局所的な定義をこれに置き換える。<br>・管理画面のログインを `setup { sign_in_as(admins(:one)) }` に揃え（`Admin.take` をやめる）、使われていない admins(:two) を消す。<br>・フィクスチャの呼び出しを覆い隠している局所変数 `words` の名前を変える。<br>・422 の記号を `:unprocessable_content` に揃える（アプリ側の10か所も揃える。値はどちらも 422）。 | テストの手本が1つになる | test/test_helper.rb、管理系のテスト14ファイル、該当するテストとコントローラ | 低 | —（既存のテストが守る） | T-11、T-14、T-15、T-17、T-18、C-22 |
| C3-12 | **読み由来の派生値の組み立てを1か所にする**。<br>・`WordSense.reading_derivations(reading)`（5つの値を Hash で返す）を作り、before_validation・backfill:reading_metrics・backfill:verify の3か所がそれを使う。<br>・reading_metrics と verify に ring_crossing_count を加える。<br>・verify では、words の代表値も WordSenseMetrics の集計と突き合わせる。<br>・reading_metrics の最後に `WordSenseMetrics.refresh!` を呼ぶ（update_columns はコールバックを通らないため）。<br>・D1-04 と組にして行う。 | 派生値の出どころが1つになり、新しい派生列の足し忘れが起きにくくなる（ring_crossing_count で1回起きている） | app/models/word_sense.rb、lib/tasks/backfill.rake、test/tasks/backfill_task_test.rb、docs/data-model.md、CLAUDE.md | 中（本番データを修復する手順に関わる。rake の出力が変わる） | T0-11。ring_crossing_count を壊して検出・修復されることを確かめるテストは、本体と同時に足す | M-01、CFG-02、T-06、DOC-05 |
| C3-13 | **ビューで派生値を計算し直すのをやめる**。_kana_ring は保存列の ring_crossing_count を使う（C3-12 で verify の対象になった後に行う）。到達しない else も消す | 表示と保存列の出どころが1つになる | app/views/words/_kana_ring.html.erb、words/show.html.erb | 低 | C3-12 の後。詳細ページの円環の既存テスト | M-17、M-15 |
| C3-14 | **代表語義と語義の順序を1か所で定める**。<br>・`Word#primary_sense`（最小の id）と `Word#ordered_senses` を作る。<br>・これを使う箇所: related_words・shiritori_words・word_share_card・proposal_application・bulk_annotation と、ホーム・一覧・詳細のビュー。<br>・ホームの「読みが長い」の数値（先頭の語義の値か、max_reading_length か）は値が変わりうるので対象外とする（§7.1）。 | 「代表の語義」の定義が1つになる | app/models（word・related_words・shiritori_words・word_share_card・proposal_application・bulk_annotation）、app/views（home/index・words/_entry_row・words/show・words/index） | 中 | T0-05 | M-11、C-02 |
| C3-15 | **かなの畳み込みを KanaFold にまとめる**。<br>・RhythmPattern と MoraCount にある同じコピー（カタカナ→ひらがな）を共有にする。<br>・NFKC を掛けるひらがな→カタカナの3実装（word_request_duplicate_check・kana_row・site_statistics）を `KanaFold.to_katakana` にする。<br>・WordCandidateDuplicateCheck が WordRequestDuplicateCheck.fold に依存しているのを、KanaFold への依存にする。<br>・NFKC を掛けない2実装（search_regexp・words_helper）と ReadingExtractor（ゕゖ を落とす範囲）は、今の変換を名前付きで保つか、KanaFold との違いをコメントに書く。 | 8通りある書き方の手本が1つになる | app/models の該当ファイル（新規 kana_fold.rb）、app/helpers/words_helper.rb、app/services/reading_extractor.rb | 中（RhythmPattern / MoraCount は保存済みの派生値に関わる） | 各呼び出し元で、半角カナ・合成濁点・ゔ・ゕゖ を含む入力の現在の出力を固定するテストを先に足す | M-04 |
| C3-16 | **絶対 URL の組み立てを SiteUrl にまとめる**。<br>・canonical_host を直接読んでいる10か所以上と、3つの流儀（手で組み立てる・absolute_site_url・パスの直書き）を SiteUrl（host / absolute(path) / 既定の og 画像パス）に寄せる。<br>・共有カードを焼けるかどうかの判定（ヘルパとコントローラの2か所）も、WordShareCard の1メソッドにする。 | URL の手本が1つになる | app/controllers（llms・robots・sitemaps・share_cards）、app/helpers/application_helper.rb・structured_data_helper.rb・words_helper.rb、jbuilder・builder・llms のテンプレート、pages/about、app/models/word_share_card.rb | 中（公開の出力に触れる。文字列は同一） | T0-01・T0-04 と、既存の meta_tags・structured_data・sitemaps・llms・robots・share_cards のテスト | C-05 |
| C3-17 | **1語の直列化で使う共通部品を1か所にまとめる**。<br>・ジャンルのパスの区切り（i18n の genre_separator と、直書きの " › "）。<br>・ライセンスの名前と URL（structured_data_helper・_license.json.jbuilder・about・ja.yml）。<br>・出力の文字列は変えない（llms-full の凡例の誤りは §7.1）。 | 同じ語彙が画面ごとにずれる事態を防ぐ | app/helpers、app/views（jbuilder・llms・about・admin の該当ビュー）、config/locales/ja.yml | 中 | T0-01。既存の structured_data_test・llms_controller_test | C-06 |
| C3-18 | **コントローラにある業務規則をモデルへ移す**。<br>・今日の一語を `Word.featured_on(date)` にする。<br>・新着順を WordSort の `"created_desc"`（同じ並び）に揃える。<br>・Atom 用の依存レコードを `Word#feed_cache_dependencies` として cache_dependencies の隣に置く。<br>・annotations_controller で4回ある提案の取得を before_action にする。<br>・管理一覧で、ジャンルを配下まで広げる処理を WordSense のスコープ1つにする（**要確認**: 公開検索と意味が一致するかを先に確かめる）。 | 規則を1か所で定めることになり、2つの画面が別々の結果を出す事態を防ぐ | app/controllers（home・words・admin/annotations・admin/words）、app/models/word.rb・word_sense.rb | 中 | T0-04。管理一覧のジャンル絞り込みの特性テスト | C-11 |
| C3-19 | **JavaScript の重複を共有モジュールにまとめる**。<br>・「表示中の語義」「全部完了しているか」の判定（publish_guard と deck で同じ処理）を、`controllers/support/` の関数にする。<br>・genre_filter の count を target として宣言する。<br>・vowel_graph の文言を、ja.yml の `searches.vowel_transition_value`（`%{}` 記法）の1本にする。 | 判定と文言の手本が1つになる | publish_guard・deck・genre_filter・vowel_graph の各コントローラ、_genre_filter・_vowel_graph、ja.yml | 中 | 既存の console・deck・stats_vowel_graph のシステムテスト。削除済みの語義を数えないことを追加する | J-05、J-13、J-14 |
| C3-20 | **検索スライダーの値と文言をヘルパから渡す**。10 / 30 と「N文字以上」などの文言を、reading_counter_data と同じ形の data 値にする。JS 側のフォールバックの定数は消す | 収録基準を変えたときにスライダーだけ取り残される事態を防ぐ | range_slider_controller.js、searches/index.html.erb、app/helpers/searches_helper.rb、ja.yml | 中（/search の HTML に data 属性が増える。意味構造は変わらない） | T0-08 | J-07、C-17 |
| C3-21 | **CSS の二重定義を1つにする**（見た目は変えない）。<br>・`.section-heading` の2つの定義を、実際に効いている値で1つにする。<br>・`.stats-grid` の 767px の gap を `.stats-grid--rows` のそばへ移す。<br>・`.is-admin` のトークンの2ブロックを1つにする。 | どの値が効くかを1か所を読めば判断できる | components.css、admin.css | 中（カスケードの順序に依存する） | T0-09。代表ページの computed style を前後で比べる（一時スクリプト） | S-03、S-07 |
| C3-22 | **テストで公開語を作る方法を create_published_word に揃える**。いま `annotated_at` だけを立てて作っている24か所を、1ファイルずつ移す（語の状態が done に変わるので、キューに関わるテストに混ざらないかを1件ずつ確かめる） | 本番では起きない状態（公開済みなのに未対応）をテストで作らなくなる | test の該当ファイル | 中 | C3-11 | T-08 |
| C3-23 | **システムテストの操作ヘルパを ApplicationSystemTestCase に集める**。type_japanese・press・click_row の系統・with_window_size を移し、環境の制約の説明も1か所にまとめる（**要確認**: 実行して、どの入力手段が今の Chrome で通るかを確かめてから行う） | system テストの書き方の手本が1つになる | test/application_system_test_case.rb、system テスト4ファイル | 中（system テストは不安定になりやすい） | 変更後に test:system を3回続けて通す | T-09 |

### 段階4: AI 向けの案内の整備（フェーズ4）

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| G4-01 | **CLAUDE.md を 200 行程度に再編する**。<br>・中身を「厳守事項」「正典パターン（手本ファイル付き。§4 の定義）」「どこに何があるかの地図（ディレクトリ → 役割 → 手本）」「合格判定コマンド」の4つに絞り、詳細は docs へリンクする。<br>・デザインの節（約78行）は design.md へ移し、禁止事項だけを残す。<br>・監査 DOC の再編案（[audits/docs-guides.md](audits/docs-guides.md) §2）に従う。 | 最初に読む文書だけで、正しい手本と禁止事項に辿り着ける | CLAUDE.md、docs/design.md、docs/overview.md | 中（AI の振る舞いに直結する） | — | DOC-07、DOC-12、M-03、C-15、C-21、CFG-12 |
| G4-02 | **docs/history/ を作り、歴史と記録を隔離する**。<br>・移すもの: changelog.md、performance-report.md、launch-checklist の解禁の記録、design.md の改訂履歴と試作・計測の記録、stats.md の経緯と実装フェーズ、growth-strategy の現状評価、issues.md のうち失効した確定事項。<br>・各文書の冒頭に「現行の仕様ではない」と書く。<br>・「再提案しない」ための規約は、design.md の禁止事項の節にまとめて現行のまま残す。<br>・リンクを張り替える。 | 現行の仕様と経緯を取り違えなくなる | docs/ 配下 | 低 | — | DOC-12、SPEC-01、SPEC-11、SPEC-22 |
| G4-03 | **docs が現行のコードと一致しているかを最終確認する**。<br>・overview の画面一覧を確かめる。<br>・環境変数の表に「Rails / Puma の標準」「テスト用」「Actions のシークレット」の欄を足す。<br>・外部コマンドの表に「本番での有無」を足す。<br>・運用の章（デプロイ・CI・cron・claude.ai 用のスキル束の再生成）を新設する。<br>・JS の地図（コントローラの一覧・独自イベント・DOM の約束事）、CSS の実際の配置、DB 制約とモデルの検証の対応表、単一の出典の表を置く。<br>・件数は書かず、出どころを指す。 | 探索の手数を減らす | docs/overview.md、docs/data-model.md、docs/design.md | 低 | — | DOC-07、DOC-08、DOC-13、CFG-08、CFG-09、CFG-11、CFG-13、J-02、J-15、S-02、SPEC-12 |
| G4-04 | **コメントを「なぜ」だけにする**。<br>・直後のコードを言い換えただけのコメントを消す。見積もり: モデル 60〜80、JS 約30、コントローラ・ビュー・テストはそれぞれ2〜3割。<br>・残すのは、なぜ・不変条件・外部との約束・長いファイルの区画見出し。<br>・経緯（日付・Issue 番号・計測値）は、docs/history か changelog へ移す。<br>・領域ごとにコミットする。 | 古くなって嘘になるコメントの発生源を減らす | app/、lib/、config/、test/ | 低（分量が多い） | — | 各報告の「コメントの傾向」 |
| G4-05 | この計画書と監査の記録を docs/history/ へ移す（完了時） | 作業文書を現行の仕様から分ける | docs/refactoring/ | 低 | — | — |

## 6. 実行順序

「文書・コメントの矛盾解消」と「リスクの低いもの」を先に行う。

1. **第1群（AI の操作を誤らせる嘘を先に消す）**: D1-01 → D1-02 → D1-03 → D1-05
2. **第2群（残りの文書・コメント）**: D1-06 〜 D1-17（D1-04 は除く。C3-12 と組にして行う）
3. **第3群（残骸の削除）**: R2-01 〜 R2-06
4. **第4群（特性テスト）**: T0-01 〜 T0-12
5. **第5群（正典への集約）**: C3-01 → … → C3-23（表の順。C3-12 は D1-04 と組にする）
6. **第6群（AI 向けの案内）**: G4-01 → G4-02 → G4-03 → G4-04 → G4-05

作業の決まり:

- **1項目 = 1コミット以上**にする。特性テストは本体とは別のコミットにして、先に入れる。コミットメッセージは日本語で書き、接頭辞は `docs:` / `test:` / `refactor:` / `chore:` を使う。
- 各コミットの前に、§0.3 を全部通す。
- 「要確認」の付いた項目は、実測・実行で確かめてから着手し、結果を該当項目か §8 に書き足す。
- **計画外の問題を見つけたら、その場では直さず §8 に記録する**。
- **サブエージェントに並列で任せるのは、第2群と G4-04 だけ**にする。担当が重ならないように、ディレクトリ（models / controllers・views / javascript / stylesheets / config・lib / test / docs）で分ける。同時に動かすのは2〜3体までにする（フェーズ1では、8体を同時に動かして利用上限で全体が止まった）。統合した後に §0.3 をやり直す。
- 所有者の作業中のファイル（§0.2）はコミットに含めない。push はしない。

## 7. 実施しないこと（理由つき）

### 7.1 外部から見える振る舞いが変わるもの（範囲外で見つかった不具合を含む）

直すと出力や挙動が変わるので、この改修では直さない。このうちコメントで表明できるものは、段階1で表明する。**別の PR で直すことを推奨する**（特に C-01・C-03・J-03・J-17）。

| ID | 内容 | 変わるもの |
|---|---|---|
| C-01 | `/words` から「条件を変える」で `/search` へ移ると、条件が許可されずに落ちる（不具合）。落ちるのは、スカラ形の first_char・last_char・part_of_speech_id・entity_type_id・linguistic_feature_id と、reading_length・mora_count・vowel_transition | /search のフォームの初期状態 |
| C-02 | ホームの「読みが長い」の数値は先頭の語義の読みの長さを使っており、並び順（max_reading_length）とずれることがある | ホームの表示値 |
| C-03 | 詳細ページと Atom を public で HTTP キャッシュしているが、同じ HTML に、ログイン中だけ出る差分（ヘッダーの管理リンクとログアウトのフォーム）がある。ETag に認証状態を入れるか、ログイン中は private にする | Cache-Control / ETag |
| C-06 | llms-full.txt の凡例が「A=英字」になっている（小文字の a は別の文字種） | 公開テキスト |
| C-07 | Atom の `<published>` が created_at、`<id>` が request.host になっている | フィードの中身 |
| C-18 | フッターの管理リンク（admin_words_path）と、ヘッダーのリンク（admin_root_path）が違う | リンク先 |
| J-03 | 語義を複製すると、削除して非表示にした特徴の行が、見えないまま新しい語義に付いて保存される（管理画面の不具合。**要再現**） | 保存される内容 |
| J-17 | コピーボタンを2秒以内に2回押すと、「コピーしました」のまま元に戻らない（公開の詳細ページ） | ボタンの表示 |
| J-09 | nav_drawer は Turbo のキャッシュの前に閉じないので、「戻る」でドロワーが開いたまま復元されうる（推測） | 「戻る」の表示 |
| J-10 | queue_nav は、ボタンの上で押した Enter も保存に使う。入力中かどうかの判定が5通りあり、統一すると挙動が変わる | 管理画面のショートカット |
| J-04 | genre_picker は、子ジャンルの取得に失敗しても黙って捨てる | 失敗時の表示 |
| M-09 | 別表記や特徴の該当部分だけを変えたとき、詳細ページの ETag が変わらない疑いがある（**要調査**） | ETag |
| M-12 | 管理画面での提案の取り込みが、` ```json ` のフェンス付きの JSON を受け付けない | 受理範囲 |
| M-14 | ReadingExtractor の MeCab 呼び出しにタイムアウトが無い（CLAUDE.md の規約に反する）。足すと、長い入力で読みが空欄になりうる | 一括登録の読み |
| M-16 | 読みの改行を、収録リクエストでは空白に置き換え、語義では取り除く（処理が2通りある） | 保存される読み |
| M-18 | WordRanking の Rails.cache に race_condition_ttl が無い | キャッシュの作り直し方 |
| SPEC-13 | 収録基準（読み10文字以上）をモデルで検証する | 保存の可否 |
| CFG-08 | INDEXING_ENABLED は値を見ず、設定されているかどうかだけで決まる（`false` でも解禁になる）。Boolean として解釈するように変えるには、本番の値の確認が要る | noindex |
| CFG-12 | ja.yml の errors.messages に `greater_than_or_equal_to` が無い（足すとエラーの文言が変わる）。test で raise_on_missing_translations を有効にする件も、既存のテストが落ちうるので別途扱う | エラーの文言 |
| CFG-13 | DB にしか無い制約（admins.username の一意など）に、モデルの検証を足す。長さの上限をモデルの定数に移す | 検証の結果 |
| J-08・S-08 | Plotly のパレットをトークンから作る | ダークでのグラフの色 |
| J-11 | theme-color を読むトークンを変える | ブラウザの UI の色 |
| J-15 | /stats の段階的強化の流儀を揃える | /stats の HTML |
| S-04 | `.entry-row__go`（表示されないアイコン）をビューから消す | 公開 HTML |
| — | `sessions/new` の `value: params[:username]` | 管理者認証の画面には触れない |

### 7.2 スキーマ・インフラ・依存の変更

| ID | 内容 | 理由 |
|---|---|---|
| DOC-01・CFG-01 | deploy.yml を、CI が成功した後に走らせる（`workflow_run` など） | インフラの変更。GitHub のブランチ保護（main への merge に CI の通過が必須か）も未確認。別途相談する |
| CFG-14・C-16 | `require "rails/all"` を、使っているフレームワークだけに絞る（Action Cable・Active Storage・Action Mailbox のルートが生えている） | フレームワークの構成の変更。eager load の確認が要る |
| CFG-15 | config/puma.rb で、単一モードでの `preload_app!` の分岐を消す | 本番の起動設定 |
| J-11・C-22 | CSP を導入する（`nonce: true` は効いていない） | GA4・Plotly の読み込みに影響する |
| CFG-04 | `word_sense_features.target` / `target_reading` を as_ci にする | スキーマの変更 |
| M-20 | 公開状態を annotated_at と annotation_status の2列で持つ設計を見直す | スキーマの変更 |

### 7.3 既存テストの削除・期待値の変更

「既存テストの期待値を変えない」という制約に当たるので、この改修では行わない。CLAUDE.md の方針（役目を終えたテストは残さない）には沿うものなので、承認があれば別の PR で整理する。

- T-02: 未ログインの拒否を個別に検証しているテスト3本（admin_authentication_test と重複している）を消す。
- T-13: 同じ式を検証している重複テスト、廃止した機能の不在確認（related_words、pages の `.page-toc`）、`assert_routing` の置き換え、`_exclude` を2つの層で検証している件。
- SPEC-24: pages_controller_test の `.image-slot` の不在確認。
- T-10: word_request_form_test のうち、サーバの描画で確かめられる部分を結合テストへ移す。
- T-17: 画面の文言を直書きしている assert を、I18n.t の参照にする。
- C-19: 一括登録の2画面でフラッシュが二重に出る（テストが現状を固定している）。
- tag_kind_test の意味の無い assert を消す。テスト用の参照実装・メソッド（`Levenshtein.far_apart?` / `distance` など、`WordRequestDuplicateCheck::Match#exact?`、`MorphemeCloud::Placed#top` など）を消す。いずれもテストの変更が伴うので、消さずに「テスト用」と注記する（D1-12）。

### 7.4 見た目が変わる CSS の変更

- S-11: design.md の規則から外れている箇所。2px の罫、box-shadow のリング、reduced-motion の対象外になっている transition、円環の線幅 1.2、ヒーローの 26px、767px 以下で 16px にする入力欄の漏れ。どちらを正とするかはオーナーが判断する。
- S-06: 値が少しずつ違う部品の統一。フォーカスの輪、下線タブ、5系統ある表、キーの表示、白い地に白い面を重ねた「見えない囲い」。
- S-07: 管理画面では `--radius` が 3px なのに、`--radius-sm` が 6px のまま。
- S-02: 管理用の CSS を、公開ページでは読まないようにする（配信する CSS が変わる）。
- SPEC-20: color-mix の下地（transparent と `--bg`）を統一する。

### 7.5 オーナー判断が要るもの

- **S-01 管理画面のダーク表示**: admin.css の上書きがライトの値で固定されており、ダークでは補足の文字がほぼ読めない（既知）。ダークに対応するか、管理画面をライトに固定するか。
- **SPEC-07・C-08 「ジャンル数」の定義**: 画面ごとに3通りある。ホームは小分類の総数、/genres は公開語義があるジャンルの数（ジャンル無しを含みうる）、/stats は使われている小分類の数。どれに揃えるか。この改修では、コメントの誤り（「同じ定義に揃える」）だけを直す。
- **DOC-11・SPEC-19 「言語的特徴だけの再調査」の書き出し**: 受け取るスキルが無い（確定事項 32・37）。撤去するか、使わない旨を画面と research/README に書くか。
- **CFG-06 開発用のダミーデータ**: 2系統ある。`db/seeds/development.rb` は公開状態の語を作り、`bin/rails dev:sample_data` は未公開の語とカタログに無いマスタを作る。どちらを正とするか。
- **CFG-14 Dockerfile 一式**: Dockerfile・bin/docker-entrypoint・.dockerignore は、どの文書にも言及が無い。残すか。
- **D1-09 の方針**: 実装（CSS）を正として design.md を直す。文書のほうを正としたい項目があれば、承認のときに指定してほしい。

### 7.6 所有者の作業中のファイル

所有者がコミットした後に、§8 へ移して扱う。

- `README.md`: 合格判定コマンドの連結形（DOC-02）。デプロイの記述は、作業中の差分ですでに deploy.yml に触れている。
- `.claude/skills/word-expansion-research/SKILL.md`: 旧フローの記述（DOC-03）。
  - 作業中の差分で `bin/rails runner` と `reading_length.rb` を持ち込んでいる。
  - `reading_length.rb` は ReadingExtractor の private メソッドを `send` で呼んでいるので、C3-04・C3-15 で ReadingExtractor を変えるときに影響しうる。
- `.claude/commands/expand.md`。

### 7.7 効果に比べて分量・リスクが大きいもの（今回は見送る）

- **CSS**
  - CSS をファイル間で移動する（S-02。カスケードの順序が変わる）。
  - 余白の px の直書き約320か所をトークンにする（S-07）。
  - `font-weight: 400` の49か所を整理する（要素ごとの確認が要る。S-05）。
  - 見た目が完全に同じ規則をまとめる（S-06。規則の位置が動く）。
- **ビューの統合**
  - 50音のヒートマップの描画をパーシャルにまとめる（C-10）。
  - ページネーションのマークアップをまとめる（C-09）。
- **JavaScript**
  - DOM の生成方式を統一する（J-16）。
  - 「その場追加」の二重実装をまとめる（J-04）。
  - サーバ側の規則を JS へ受け渡す（J-06）。
- **モデル**
  - 結果オブジェクトの形を統一する（M-19）。
  - トランザクションの張り方を統一する（M-13。今回は MySQL 依存の注記だけ）。
  - 重複チェックの3実装をまとめる（M-06。違いは意図なので注記だけ）。
- **書き方の全面統一**
  - Strong Parameters を全面的に統一する（C-15。生の `params[:x]` が約60か所ある）。
  - i18n の相対キーと絶対キーを全面的に統一する（CFG-12・C-21。新しいコードの規則だけを決める）。
  - llms テンプレートを i18n にする（C-21）。
  - 日付の書式を `l()` に統一する（C-22。表示が変わりうる）。
  - マスタを新設する3つの経路の正規化を統一する（C-20。要調査）。
- **検索エンジンから見える挙動**: インデックスしてよいかの規則が、ビュー・ヘルパ・モデルの3層にある（C-17）。今回は触らない（CLAUDE.md の注意に従う）。
- **Rails の雛形**: ApplicationMailer・ApplicationJob・メーラーのレイアウトは、使うときの基底になるので残す。地図に「未使用の雛形」と書く。

## 8. 追加候補（フェーズ3で見つけた計画外の問題）

| 日付 | 内容 | 見つけた項目 | 判断 |
|---|---|---|---|
| — | （フェーズ3で記録する） | — | — |

## 9. 付録: 監査 ID と改修項目の対応

すべての指摘が、改修項目か §7 のどこかに対応している。

- **M**: M-01→C3-12 / M-02→D1-04 / M-03→D1-12・G4-01 / M-04→C3-15 / M-05→C3-02 / M-06→D1-12（統合は §7.7） / M-07→D1-03 / M-08→D1-13 / M-09→§7.1 / M-10→C3-01 / M-11→C3-14 / M-12→C3-03（提案の取り込みは §7.1） / M-13→D1-13（統一は §7.7。intake のコメントは不採用） / M-14→C3-04（タイムアウトは §7.1） / M-15→R2-01・C3-13・D1-12 / M-16→D1-12・D1-03（読みの改行は §7.1） / M-17→C3-13・C3-01・C3-10 / M-18→C3-10・D1-13（race_condition_ttl は §7.1） / M-19→§7.7 / M-20→D1-13（設計の見直しは §7.2） / M-21→D1-13
- **C**: C-01→D1-14（修正は §7.1） / C-02→C3-14（ホームの数値は §7.1） / C-03→D1-14（修正は §7.1） / C-04→C3-10 / C-05→C3-16 / C-06→C3-17（llms の凡例は §7.1） / C-07→§7.1 / C-08→C3-10（ジャンル数は §7.5） / C-09→C3-08（マークアップは §7.7） / C-10→C3-09（描画は §7.7） / C-11→C3-18 / C-12→D1-12 / C-13→C3-07 / C-14→C3-07 / C-15→C3-05・G4-01（全面統一は §7.7） / C-16→R2-01・R2-02（エンジンのルートは §7.2、sessions は §7.1、雛形は §7.7） / C-17→C3-01・C3-20（インデックス可否の規則は §7.7） / C-18→C3-06（フッターのリンクは §7.1） / C-19→§7.3 / C-20→§7.7 / C-21→G4-01（全面統一は §7.7） / C-22→C3-11・C3-05・D1-14（日付の書式は §7.7） / C-23→D1-14
- **J**: J-01→D1-15 / J-02→G4-03 / J-03→§7.1 / J-04→§7.1・§7.7 / J-05→C3-19 / J-06→D1-15（受け渡しは §7.7） / J-07→C3-20 / J-08→D1-15（パレットは §7.1） / J-09→D1-15（Turbo のキャッシュは §7.1） / J-10→§7.1 / J-11→D1-14（theme-color は §7.1、CSP は §7.2） / J-12→D1-09 / J-13→C3-19 / J-14→C3-19 / J-15→G4-03（/stats の移行は §7.1） / J-16→D1-15（統一は §7.7） / J-17→§7.1 / J-18→D1-15・D1-17 / J-19→R2-03・D1-15 / J-20→D1-15
- **S**: S-01→D1-09・§7.5 / S-02→D1-16・G4-03（移動は §7.7、公開ページで読まない件は §7.4） / S-03→C3-21・D1-16・R2-04 / S-04→R2-04（`.entry-row__go` は §7.1） / S-05→R2-04（font-weight は §7.7） / S-06→§7.4・§7.7 / S-07→D1-16・R2-04・C3-21（`--radius-sm` は §7.4、px のトークン化は §7.7） / S-08→T0-09・D1-14（パレットは §7.1） / S-09→C3-06 / S-10→D1-16 / S-11→§7.4 / S-12→D1-16 / S-13→D1-09
- **CFG**: CFG-01→D1-01（CI を待たせる件は §7.2） / CFG-02→C3-12・D1-04 / CFG-03→D1-03 / CFG-04→D1-03・T0-06（target の as_ci 化は §7.2） / CFG-05→D1-01 / CFG-06→§7.5 / CFG-07→C3-01・D1-12・D1-13 / CFG-08→D1-17・G4-03（解釈の変更は §7.1） / CFG-09→D1-02・D1-17 / CFG-10→D1-15 / CFG-11→D1-07・G4-03 / CFG-12→R2-02・G4-01（不足キーは §7.1、全面統一は §7.7） / CFG-13→G4-03（検証の追加は §7.1） / CFG-14→R2-05（rails/all は §7.2、Dockerfile は §7.5） / CFG-15→D1-17（分岐の削除は §7.2） / CFG-16→D1-17 / CFG-17→D1-17・R2-05 / CFG-18→D1-17
- **T**: T-01→T0-01 / T-02→D1-05・D1-17（3本の削除は §7.3） / T-03→T0-02 / T-04→T0-03・C3-01 / T-05→T0-04 / T-06→T0-11・C3-12・D1-17 / T-07→R2-06 / T-08→C3-22 / T-09→C3-23・D1-17 / T-10→D1-05（テストの分割は §7.3） / T-11→C3-11・R2-06 / T-12→T0-12 / T-13→§7.3 / T-14→C3-11 / T-15→C3-11・R2-01 / T-16→C3-04 / T-17→C3-11（文言は §7.3） / T-18→C3-11 / T-19→D1-17
- **DOC**: DOC-01→D1-01（CI を待たせる件は §7.2） / DOC-02→D1-02（README は §7.6） / DOC-03→D1-06（word-expansion-research は §7.6） / DOC-04→D1-03 / DOC-05→D1-04・C3-12 / DOC-06→D1-11 / DOC-07→G4-01・G4-03・D1-12 / DOC-08→D1-09・G4-03 / DOC-09→D1-05・C3-04（タイムアウトは §7.1） / DOC-10→C3-03・D1-06 / DOC-11→§7.5 / DOC-12→G4-01・G4-02 / DOC-13→D1-17・G4-03 / DOC-14→D1-06 / DOC-15→D1-07 / DOC-16→D1-01・D1-07・D1-12・D1-17・R2-01・R2-02（dev_samples は §7.5）
- **SPEC**: SPEC-01→D1-08・G4-02 / SPEC-02→D1-09 / SPEC-03→D1-09・D1-16 / SPEC-04→D1-09・D1-16 / SPEC-05→D1-09・D1-16 / SPEC-06→D1-09 / SPEC-07→D1-14（定義の統一は §7.5） / SPEC-08→D1-11 / SPEC-09→D1-10 / SPEC-10→D1-08 / SPEC-11→D1-08・G4-02 / SPEC-12→D1-07・G4-03 / SPEC-13→D1-13・C3-01（モデルでの検証は §7.1） / SPEC-14→D1-07 / SPEC-15→D1-12・D1-14・D1-16 / SPEC-16→D1-08・D1-12・D1-17 / SPEC-17→D1-10 / SPEC-18→C3-01 / SPEC-19→§7.5 / SPEC-20→C3-01（color-mix は §7.4） / SPEC-21→D1-08 / SPEC-22→G4-02 / SPEC-23→D1-08 / SPEC-24→§7.3

## 10. 承認のときに決めてほしいこと

1. この計画（段階0〜4）を進めてよいか。外したい項目があれば ID で指定してほしい。
2. §7.5 の各項目の判断。この改修ではどれも実施しない。判断が出たら §8 に移して扱う。
3. D1-09 の方針（CSS を正として design.md を直す）でよいか。
4. 監査の記録（`docs/refactoring/audits/`）をリポジトリに残してよいか（改修が終わったら docs/history/ へ移す）。
