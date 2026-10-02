> フェーズ1の監査報告（担当: app/javascript）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# 監査報告 J：app/javascript・config/importmap.rb・vendor/javascript と、それを使うビューの data 属性

**確度の意味**
- 確認済み：コードと呼び出し元を読んで裏付けた。
- 推測：経路は読んだが、ブラウザでの再現やツールの実行はしていない。

**前提**
- ファイルの変更、テスト・DB・rake の実行は一切していない。
- 所有者の未コミットの変更（README.md・.claude/ 配下）は J 領域の外なので参照していない。

---

## 0. コントローラの棚卸し（28本すべて使用中）

**未使用の判定に使った検索**
- `data-controller="…"` と erb・ヘルパ内の `controller: "…"`。空白区切りの複数指定（`"deck publish-guard"`・`"decision-list row-select"`）も含む。
- `data-<id>-target`・`-value`・`->id#method`。
- test/ からの参照。

**結果**：未使用のコントローラ・target・value・action・メソッドは無い。例外は J-13 と J-19 に挙げたものだけ。

| # | コントローラ | 冒頭コメントの要約 | 使うビュー | system test | 食い違い |
|---|---|---|---|---|---|
|1|auto_submit|変更で「親フォーム」を送る|words/index.html.erb:101, admin/words/index.html.erb:10|なし|実際は付けた要素自身を送る（J-18）|
|2|char_type|文字種キーで入力|searches/index.html.erb:110|search_char_type_test.rb|キーを5個と記載、実際は7個（J-18）|
|3|char_type_toggle|Aa/ab の切替＋3秒の状態ラベル|searches/index.html.erb:143,157|同上（Aa 側のみ）|動きの方針と衝突（J-12）|
|4|check_all|全選択（Issue 37 用）|admin/words/index.html.erb:85, admin/word_requests/index.html.erb:27|admin_words_bulk_test.rb（toggle のみ）|用途の記載が古い（J-18）|
|5|clipboard|コピーして一時的に完了表示|words/show.html.erb:52 ほか管理画面4箇所|なし|連続で押すと表示が戻らない（J-17）|
|6|decision_list|仕分け・表記の確認の操作|word_candidates_helper.rb:19|admin_word_candidates_test.rb|—|
|7|deck|カード送り＋完了数の集計|annotation_decks/_deck.html.erb:5|admin_annotation_deck_test.rb（キー操作は未）|判定が重複（J-05）|
|8|feature_range|該当部分を範囲タップで指定|annotations/_feature_fields.html.erb:4|console test:121|「アクセント」の記述が誤り（J-08）|
|9|genre_filter|折り畳みに選択数のバッジ|searches/_genre_filter.html.erb:11|なし|宣言していない target を使う（J-13）|
|10|genre_picker|ジャンルの段階表示＋その場追加|_sense_fields.html.erb:79, admin/words/_bulk_annotation.html.erb:16|console test・bulk test|その場追加が別実装（J-04）|
|11|genre_sunburst|Plotly のサンバースト|stats/_genre_sunburst.html.erb:4|なし|色を JS に持たないと書きつつパレットを直書き（J-08）|
|12|inline_add|マスタのその場追加|_sense_fields.html.erb:57,128,159|なし|不要な export がある（J-19）|
|13|nav_drawer|「ナビ+検索パネル」|shared/_header.html.erb:4|なし|検索はもう無い。Turbo キャッシュ未対応（J-09）|
|14|nav_menu|「検索」のプルダウン|shared/_header.html.erb:41|header_nav_menu_test.rb|—|
|15|nested_form|行の追加・削除|_sense_fields.html.erb:179,233, word_requests/new.html.erb:23|word_request_form_test.rb, console test|削除（remove）は未テスト|
|16|panel_switch|セグメントでパネル切替|stats/index.html.erb:38,72, rankings/index.html.erb:20|rankings_test.rb|初期状態の作り方が2流儀（J-15）|
|17|publish_guard|公開前の確認|annotations/show.html.erb:53, _deck.html.erb:5|console・deck test|deck と判定が重複（J-05）|
|18|queue_nav|← → Enter のショートカット|annotations/show.html.erb:3|なし|先頭へのスクロールを隠れて行う・Enter を横取り（J-10, J-18）|
|19|range_slider|読みの文字数の二つまみ（10〜30）|searches/index.html.erb:42|なし|文言と境界値を直書き（J-07, J-08）|
|20|reading_choice|読み候補のチップ|admin/words/readings.html.erb:49|なし|—|
|21|reading_counter|字数と収録基準の表示|word_requests_helper.rb:7 → word_requests/_row.html.erb:4|word_request_form_test.rb:33|—（手本になる書き方）|
|22|reading_format|読みはカタカナのみ|admin/words/readings.html.erb:20|admin_words_reading_format_test.rb|規則が JS にしか無い（J-06）|
|23|row_select|一覧の行を選ぶ|word_candidates_helper.rb:19,34|admin_word_candidates_test.rb|—|
|24|sense_cloner|語義の複製|annotations/show.html.erb:78, _card.html.erb:77|console test:189（一部のみ）|削除した特徴行が復活する（J-03）|
|25|sense_completeness|最低限の項目が揃ったら完了表示|_sense_fields.html.erb:16|console:73, deck:44|—|
|26|submit_shortcut|Ctrl+Enter で送信|candidates/triages/show.html.erb:8, candidates/_import_form.html.erb:4|なし|decision_list と同じ目的の別実装（J-10）|
|27|theme|ダークモード|shared/_header.html.erb:79|theme_toggle_test.rb|処理が二重・theme-color の出どころ（J-11）|
|28|vowel_graph|母音の並びを選んで検索へ|stats/_vowel_graph.html.erb:11|stats_vowel_graph_test.rb|URL の形式を JS も持つ（J-06）|

**system test が無いコントローラ**：auto_submit, clipboard, genre_filter, genre_sunburst, inline_add, nav_drawer, queue_nav, range_slider, reading_choice, submit_shortcut。

**一部しか固定されていないもの**：
- panel_switch：stats 側の流儀は未テスト。
- nested_form：remove が未テスト。
- check_all：sync が未テスト。
- sense_cloner：複製後の値のクリアが未テスト。

---

## 指摘（重要度の高い順）

### [J-01] 「公開ページではコントローラを使わない」というコメントが事実と逆
- 観点: A ／ 確度: 確認済み
- 根拠:
  - config/importmap.rb:5「コントローラは preload しない(公開ページでは使わないため。…)」
  - controllers/index.js:2「公開ページ(コントローラ不要)では JS を読み込まず」
  - 実際は全ページのヘッダーが nav-drawer / nav-menu / theme を使っている（shared/_header.html.erb:4,41,79）。公開ページで動くのは計16本。
  - git の経緯：コメントは 11b971c（2026-07-05 10:26）で書かれ、同日 19:48 のドロワー化 7d50f63 で事実と合わなくなった。
- 問題:
  - 「公開側は JS 無しで動く」「JS を足しても公開側に影響しない」と誤読させる。
  - docs/overview.md §6「Stimulus のみ。1 コントローラ 1 目的」も実態とずれている：
    - レイアウトにインライン JS が2つある（layouts/application.html.erb:63-79 のテーマ復元、layouts/_analytics.html.erb:6-17 の GA4）。
    - deck・theme・decision_list は複数の目的を持つ。
- 提案:
  - コメントの理由を「28本を全ページで modulepreload すると未使用警告が出るので、data-controller が現れた分だけ遅延読み込みする。ヘッダーの3本は全ページで読まれる」に直す。
  - overview §6 に「インライン JS は上の2箇所だけ」と追記する。「1目的」の表現は直すか、例外を列挙する。
- 影響ファイル: config/importmap.rb, app/javascript/controllers/index.js, docs/overview.md
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要（コメントのみ）

### [J-02] コントローラ同士・ビューとの約束事が一覧されておらず、辿るのに全ファイルの grep が要る
- 観点: D・E ／ 確度: 確認済み
- 根拠（一覧になっていない約束事）:
  - **独自イベント**
    - sense_completeness:18 の `dispatch("changed")` を _deck.html.erb:7 の `sense-completeness:changed->deck#recount` が受ける。
    - genre_picker:98 と inline_add:52 の発火を _sense_fields.html.erb:18-19 が受ける。
    - char_type_toggle:26 の発火を searches/index.html.erb:144 が受ける。
    - decision_list:107,123 の発火を word_candidates_helper.rb:25 が受ける。
    - theme_controller.js:45 が document に `theme:change` を流し、genre_sunburst:27 が受ける。
  - **クラスでの約束**
    - 完了＝`is-complete`（sense_completeness:14 が付け、publish_guard:20・deck:119 が読む）。
    - 削除済み＝`.js-sense` の `style.display === "none"`。publish_guard:18-19, deck:118, nested_form:49, sense_cloner:25,61 と、サーバ描画の _sense_fields.html.erb:15, _feature_fields.html.erb:5, _variant_fields.html.erb:2 がこの表現を共有している。
  - **別ディレクトリの DOM に依存**：decision_list:47 の `.cand-word__edit`（admin/candidates/_word.html.erb）と :133 の `.cand-edit__cancel`（admin/word_candidates/edit.html.erb）。
  - **テスト基盤への依存**：controllers/application.js:7 の `window.Stimulus` を test/application_system_test_case.rb の wait_for_stimulus が使う。
  - **バブリング順への依存**：`click->deck#recount`（_deck.html.erb:7）は、内側の sense-cloner#remove が先に走ることを前提にしている。
- 問題: 片側だけ読むと約束事が見えない。クラス名の変更や window.Stimulus の削除で、エラーも出ずに壊れる。design.md は theme 以外のコントローラに触れていない。
- 提案:
  - docs/overview.md（または新設の docs/javascript.md）に「JS の地図」を置く：
    - 28本の表（画面・目的・system test）
    - 独自イベントの一覧
    - DOM の約束事（完了クラス、削除済み行＝display:none＋_destroy、data-js-only）
    - 正典パターン（末尾のまとめ1）
  - controllers/application.js:7 に「system test が参照するので消さない」と注記する。
- 影響ファイル: docs, app/javascript/controllers/application.js
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要

### [J-03] 語義を複製すると、削除（非表示）した特徴行が見えないまま新規として保存される
- 観点: E（バグ） ／ 確度: 確認済み（コードの経路を追った。ブラウザでは再現していない）
- 根拠:
  - 特徴行は新規・既存とも `_destroy` を持つ（_feature_fields.html.erb:9 `data: { nested_form_destroy: "" }`）。そのため削除は「_destroy=1 にして display:none で隠す」になる（nested_form_controller.js:55-58）。
  - 複製は id を外し（sense_cloner_controller.js:28）、`input[data-nested-form-destroy], input[data-sense-destroy]` の値を空にする（:29-30）。ただし隠した行の display:none はそのまま残る。
  - 複製元は `senses[senses.length - 1]`（:12-13）で、削除済みの語義も複製元になりうる。
- 問題:
  - 画面に見えない特徴が新しい語義に付いて保存される。
  - コメント「_destroy(語義・特徴・別表記)を初期化」（:27）が原因そのものなのに、読む側には正しい処理に見える。
- 提案:
  - 複製した直後に、`[data-nested-form-item]` のうち非表示の行を DOM から除去してから `_destroy` を初期化する。
  - 複製元は「表示中の最後の語義」にする。
- 影響ファイル: sense_cloner_controller.js
- リスク: 中 ／ 外部振る舞いへの影響: なし（管理画面のみ。バグの場合の保存内容だけが変わる）
- 先に必要な特性テスト: 不足。system test「特徴を削除してから語義を追加・保存しても、新しい語義に特徴が付かない」を先に追加する。

### [J-04] 「その場追加」の画面部品が2つ別々に実装され、失敗時の扱いも逆になっている
- 観点: B・D・E ／ 確度: 確認済み
- 根拠:
  - inline_add はサーバ描画のマークアップ＋targets＋data-action で作られている（_sense_fields.html.erb:57-70、inline_add_controller.js:16-103）。
  - genre_picker は同じ部品を createElement＋addEventListener で自作している（genre_picker_controller.js:125-186）。
  - 同じ処理が両方にある：
    - IME の判定 `event.isComposing || event.keyCode === 229`（inline_add:25 / genre_picker:147）
    - 連打防止（:38 `this.busy` / :160 `input.dataset.busy`）
    - Esc で閉じる、既存を選んだときのメッセージ
  - addEventListener で結んでいるので、複製や Turbo の復元で操作が効かなくなる。それを避けるため、接続のたびに部品を作り直している（genre_picker:19-24）。
  - 子ジャンルの取得は `catch { /* 取得失敗時は追加のみ可能 */ }`（:111）で失敗を黙って捨て、`!response.ok` も見ていない。これは inline_add:9-11「失敗の理由は必ず入力欄の隣に出す」と inline_master_creatable.rb:4-9 の方針と逆。
- 問題: 片方だけ直る。セッションが切れると、ジャンルの選択肢が何も言わずに空になる。
- 提案:
  - 正典はサーバ描画＋data-action（inline_add）。
  - ジャンル各段の追加欄は、ビューの `<template>` から複製して data-action で結ぶ。これで作り直しの回避策が要らなくなる。
  - GET 用の `getJson()` を `post()` と同じ場所に置き、失敗は必ず表示する。
  - 共通関数の置き場は `app/javascript/controllers/support/` にする。pin_all_from で自動的にピンされ、遅延ローダーは `_controller` 以外を登録しない（推測）。
- 影響ファイル: genre_picker_controller.js, inline_add_controller.js, _sense_fields.html.erb, admin/words/_bulk_annotation.html.erb
- リスク: 中 ／ 外部振る舞いへの影響: なし（管理画面のみ）
- 先に必要な特性テスト: ジャンル側は admin_annotation_console_test.rb:165-207 で固定済み。inline_add（語種・品詞・エンティティ）は未固定なので「追加すると選択状態になる」「既存の名前なら既存が選ばれる」を先に追加する。

### [J-05] 「表示中の語義がすべて完了か」の判定が2箇所に同じ文で書かれ、「削除済み」の判定は3箇所にある
- 観点: D ／ 確度: 確認済み
- 根拠:
  - publish_guard_controller.js:17-21 と deck_controller.js:117-120 が同じ処理。deck:103 に「publish-guard の判定と同じ数え方」と書いてあり、重複を自認している。
  - `style.display !== "none"` は nested_form:49 にもある。
- 提案: support モジュールに `visibleSenses(root)` と `allSensesComplete(root)` を1つだけ置き、両方から使う。
- 影響ファイル: publish_guard, deck（nested_form は任意）
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: admin_annotation_console_test.rb:32-54 と admin_annotation_deck_test.rb:44-79 で固定済み。削除済みの語義を数えないことは未固定なので追加を推奨。

### [J-06] サーバ側の規則を JS も独自に持っていて、どちらが正かがコードに書かれていない
- 観点: D ／ 確度: a〜c と e は確認済み、d は推測
- 根拠:
  - **a. 母音遷移の URL 形式**：vowel_graph_controller.js:111 `?vowel_transition=${from}-${vowels}` と word_sense_search.rb:7 `VOWEL_TRANSITION_FORMAT = /\A(\d{1,2})-([aiueo]{2,15})\z/`。JS は上限（15拍・拍位置30）を知らず、範囲外ならサーバが黙って条件を捨てる。
  - **b. 読みはカタカナのみ**：強制しているのは reading_format_controller.js:7 `/^[ァ-ヶー]+$/` だけ。
    - サーバ側は検証していない：BulkWordRegistration#entries= は strip のみ（bulk_word_registration.rb:132）、WordSense は presence のみ（word_sense.rb:39）。
    - 同じ文字クラスが reading_extractor.rb:16 と morpheme_extractor.rb:20 にもある。
  - **c. 文字種の大文字小文字の畳み込み**：char_type:28 `replaceAll(lower, upper)` と word_sense_search.rb:76 `raw.tr(LOWER, UPPER)`。記号はビューから値で渡しているので一元化できている（searches/index.html.erb:111-112）が、規則は二重。
  - **d. 読みの字数**：reading_counter:15 `[...value.trim()].length` は全角空白も落とす。WordRequestItem の `strip`（word_request_item.rb:30）と DB の `char_length`（schema.rb:168）は落とさないので、1字ずれることがある（推測）。
  - **e. 「最低限の注釈」の定義**：sense_completeness:21-28 にしか無い。
- 提案:
  - a・c・e の JS 側に「正は ◯◯」と一行で注記する。
  - b は文字クラスを Ruby の定数1つに寄せ、`data-reading-format-pattern-value` で渡す（手本は word_requests_helper.rb:4-13 の reading_counter_data）。
  - サーバ側でのカタカナ検証の追加は振る舞いが変わるので、計画書への提案のみ。
- 影響ファイル: vowel_graph, reading_format, char_type, reading_counter, sense_completeness と対応するビュー・ヘルパ
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: a は stats_vowel_graph_test.rb:57,64,67、b は admin_words_reading_format_test.rb で固定済み。

### [J-07] range_slider が文言と境界値を直書きしており、Ruby 側と二重
- 観点: A・D ／ 確度: 確認済み
- 根拠:
  - range_slider_controller.js:54-58 の `` `${lo}文字以上` `` などは、searches_helper.rb:66-74 と ja.yml:273,275,342 の文言と完全に同じ。
  - 境界値 10/30 をビューが直書き（searches/index.html.erb:43,46,49）し、JS にも `|| 10` `|| 30`（:16-17）がある。10 は WordSense::MIN_READING_LENGTH（word_sense.rb:33）と同じ値。
  - JS 内の日本語の直書き文言は、ほかに feature_range:113「（単語 未選択）」だけ。
- 問題: CLAUDE.md の「表示文言は i18n」「基準値は概念の持ち主に置く」に反する。収録基準を変えるとスライダーだけ取り残される。
- 提案:
  - reading_counter_data と同じ形の `range_slider_data` ヘルパを作り、min=WordSense::MIN_READING_LENGTH、max=名前付きの定数（候補は SiteStatistics::DISTRIBUTION_OVERFLOW_MIN。値は未確認）、文言テンプレートは t() で渡す。
  - JS のフォールバックは削除する。feature_range の文言も values で渡す。
- 影響ファイル: range_slider, feature_range, searches/index.html.erb, _feature_fields.html.erb, ヘルパ, ja.yml
- リスク: 低 ／ 外部振る舞いへの影響: なし（表示文字列は同じ）
- 先に必要な特性テスト: 不足。「つまみを動かすと 3 種類の文言が出て hidden に値が入る。上限30のとき max は空」を先に固定する。

### [J-08] デザイン刷新時の機械的な置換で、コメントが実装と矛盾したまま残っている
- 観点: A ／ 確度: 確認済み
- 根拠: ee7a328（2026-09-07）の差分で「朱」が「アクセント」に置き換えられた。
  - range_slider:42「アクセント色で示す」→ 実際の CSS は `--text`（components.css:1583-1588）。
  - feature_range:5「アクセント枠／アクセントの塗り」→ 実際は annotate.css:183-184 の `--text`／`--bg-tint`。
  - `--accent` トークンは存在しない。CLAUDE.md は「アクセントカラーを持たない」。
  - genre_sunburst:38「色は JS に持たせず CSS のトークンから読む」の直前、:16-20 に hex のパレットを直書きしている。
    - `--chart` にはダーク用の値がある（tokens.css:142）ので、パレットはダークに追従しない。
    - design.md §9.1「色はトークン以外で直書きしない」にも反する。
  - separatorColor は `--bg` を「地の色」として読む（:39-42）が、現在の本文の地は `--surface`（base.css:22）。
- 問題: 次のエージェントが存在しない「アクセント色」を探したり、パレットを正しいものと信じたりする。
- 提案:
  - コメントはすぐ直す。
  - パレットは tokens.css に `--chart-1..n`（両テーマ）を置いて実行時に読む。ダークでの見た目が変わるので計画書への提案のみ。
- 影響ファイル: range_slider, feature_range, genre_sunburst（tokens.css は提案）
- リスク: コメントは低、パレットは中 ／ 外部振る舞いへの影響: コメントはなし、パレットはあり（ダークの配色）
- 先に必要な特性テスト: パレットを変える場合、ダークでの取得を固定するテストを先に追加する。

### [J-09] 大域キーと Turbo キャッシュの扱いが混在し、nav_drawer だけ「戻る」でドロワーが開いたまま復元されうる
- 観点: B・E ／ 確度: 混在は確認済み、「戻る」での現象は推測
- 根拠:
  - **nav_menu**：data-action `click@window->…#closeOnOutside keydown.esc@window->…#close`（_header.html.erb:42）で受け、`turbo:before-cache` で閉じる（nav_menu:9-16）。
  - **nav_drawer**：同じ Esc を connect で `document.addEventListener("keydown")` で受けている（nav_drawer:9-12）。before-cache の処理が無いのに `.is-open` と `body.nav-drawer-open`（overflow:hidden、layout.css:802-804）を付ける。
  - addEventListener 派：queue_nav:10, deck:12-15, genre_sunburst:27。@window 派：word_candidates_helper.rb:8-13,24。
  - 冒頭コメント「ナビ+検索パネル」（nav_drawer:3）は、ヘッダーの検索撤去（368244f, 2026-07-22）の後も残っている。
- 提案:
  - 正典は data-action の `@window`/`@document`（`turbo:before-cache@document->x#close` を含む）。
  - addEventListener は matchMedia（theme:13-21）や要素の外の入力欄（feature_range:14-22）に限り、disconnect で必ず外す。
  - nav_drawer をこの形に揃え、コメントを直す。
- 影響ファイル: nav_drawer, queue_nav, deck, genre_sunburst と対応するビュー
- リスク: 低〜中 ／ 外部振る舞いへの影響: 「戻る」でのドロワーの見え方だけ（直る方向）
- 先に必要な特性テスト: 不足。モバイル幅で「開く→Esc で閉じる→遷移して戻ると閉じている」を先に追加する。

### [J-10] 「入力中はショートカットを無効にする」判定が5通り、Ctrl+Enter の送信が2実装、queue_nav はボタン上の Enter も奪う
- 観点: B ／ 確度: 混在は確認済み、Enter の実害は推測
- 根拠:
  - 判定の5通り：
    - queue_nav:27-28（input・textarea のみ）
    - deck:37-38（select も含む）
    - decision_list:4 と row_select:6（同じ文字列の `EDITABLE` を別々に定義）
    - inline_add:25 と genre_picker:147（isComposing と keyCode 229）
    - submit_shortcut:7（isComposing のみ）
  - Ctrl+Enter の送信は submit_shortcut:7-10 と decision_list:77-80 の2つ。
  - queue_nav:30-32 はフォーカスがボタンでも Enter で送信する。ジャンルのチップ（`button.ann-chip`、_sense_fields.html.erb:99）にフォーカスがあると、Enter で保存・公開になる。
- 提案:
  - support モジュールに `EDITABLE` と `isTyping(event)` を1つ置き、全コントローラで使う。
  - queue_nav は button・a・select・summary の上では Enter を無視する。
  - 手本は decision_list:3-4,73-75。
- 影響ファイル: 上記6コントローラ
- リスク: 中 ／ 外部振る舞いへの影響: なし（管理画面のみ）
- 先に必要な特性テスト: queue_nav には無い。「← → で移動できる」「入力欄やボタンの上では効かない」を先に追加する。

### [J-11] テーマの復元と同期が2箇所に重複し、theme-color の出どころが画面の実際の色とずれている（nonce も効いていない）
- 観点: D・E ／ 確度: 確認済み
- 根拠:
  - localStorage のキー "theme" が theme_controller.js:7 と application.html.erb:66 の2箇所にある（テストでは theme_toggle_test.rb:94,107）。
  - theme-color を `--bg` から読む処理が :40-43 と application.html.erb:73-77 に二重にある。ところがヘッダーは `--bg-soft`（layout.css:8-10）、本文は `--surface` で、`--bg` はどちらでもない。
  - `javascript_tag nonce: true`（application.html.erb:63）は CSP が未設定なので効いていない（content_security_policy.rb は全行コメント）。GA4 のインライン script（_analytics.html.erb:6）には nonce が無い。
- 問題: 片方だけ直すと、ちらつきや不一致が起きる。CSP を入れた時点で GA4 と Plotly の読み込みが止まる、という前提がどこにも書かれていない。
- 提案:
  - 2箇所に相互参照のコメント（キー名と、読むトークン）を置く。
  - layout に「CSP は未設定」と明記する。
  - theme-color を別のトークンにする変更は、ブラウザ UI の色が変わるので計画書への提案のみ。
- 影響ファイル: theme_controller.js, layouts/application.html.erb, _analytics.html.erb
- リスク: 低 ／ 外部振る舞いへの影響: コメントだけならなし
- 先に必要な特性テスト: theme_toggle_test.rb で固定済み（theme-color は未固定）。

### [J-12] 「動きはホームの印だけ、他は hover の色変化だけ」という方針と、JS が起こす動きが一致しない
- 観点: A ／ 確度: 確認済み
- 根拠:
  - CLAUDE.md と design.md:55-56 の方針に対し、次の動きがある：
    - 文字種トグルの状態ラベルの3秒フェード（char_type_toggle:9,29-37、components.css:1483）
    - ドロワーのスライド（layout.css:736）とハンバーガーの変形（:124）
    - キャレットの回転（:216）
  - reduced-motion の対応はラベルだけ（components.css:1490-1492）。
  - スクロール連動や視差の JS は無く、ホームの印にも JS は無い（28本を通読して確認）。
- 問題: 方針を字義通りに適用すると既存の UI を壊す。逆に「方針違反も許される」と誤解させる。
- 提案:
  - design.md §4 に例外（状態変化に伴う 250ms 以下の transition と、状態ラベル）を明記する。
  - 実装側を方針に合わせる案は見た目が変わるので、計画書への提案のみ。
- 影響ファイル: docs/design.md, CLAUDE.md
- リスク: 低 ／ 外部振る舞いへの影響: 文書だけならなし
- 先に必要な特性テスト: 不要

### [J-13] 要素ごとの引数の渡し方が混在し、genre_filter は宣言していない target を属性で直接探している
- 観点: B ／ 確度: 確認済み
- 根拠:
  - Stimulus の action params を使っているのは char_type だけ（:13 と searches/index.html.erb:125）。
  - ほかは生の dataset を読む：panel_switch:19, reading_choice:9, deck:52, decision_list:94,99, genre_picker:70, vowel_graph:106-110。char_type_toggle:22 は文言まで dataset で受け取る。
  - genre_filter:9 は `static targets = ["fold"]` と宣言しながら、:14 で `querySelector("[data-genre-filter-target=count]")` を使う（ビューは _genre_filter.html.erb:25,46）。
- 問題: target に見えて target でないので、`countTargets` は使えず、改名の際に見落とされる。
- 提案:
  - genre_filter は `count` を target として宣言する。
  - 新しいコードの正典は「アクションの引数は action params、文言は values」。
  - data-flag と data-index はテストが参照しているので移行しない（admin_word_candidates_test.rb:52、admin_annotation_deck_test.rb:35,40）。
- 影響ファイル: genre_filter_controller.js
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: バッジの初期表示は searches_controller_test.rb:114 で固定済み。JS による更新は未固定。

### [J-14] JS に渡す i18n 文言のプレースホルダ記法が2種類あり、同じ文が ja.yml に2本ある
- 観点: B・D ／ 確度: 確認済み
- 根拠:
  - ja.yml:1262 `"{from}〜{to}拍目: {rows}"` を vowel_graph:107-110 が `.replace` で置換している。
  - ほかは `%{name}` 記法：ja.yml:552 `%{count}`（row_select:277）、:961 `%{status}`（inline_add:125）。
  - 同じ文が ja.yml:225 `vowel_transition_value` にもあり、searches_helper.rb:59-64 が使っている。
- 提案: `%{name}` に統一し、vowel_graph には `searches.vowel_transition_value` を渡して1本にする。
- 影響ファイル: vowel_graph, stats/_vowel_graph.html.erb:13, ja.yml
- リスク: 低 ／ 外部振る舞いへの影響: なし（表示文字列は同じ）
- 先に必要な特性テスト: 選んだ並びを示す文言の assert を stats_vowel_graph_test.rb に追加する。

### [J-15] JS が無いときの初期状態の作り方が複数あり、panel_switch は1本の中に2つの流儀を持つ
- 観点: B ／ 確度: 確認済み
- 根拠:
  - panel_switch の2流儀：
    - サーバが hidden を付ける（stats/index.html.erb:49,77）。JS が無いとモーラ数や期間別の表を見られない。
    - 接続時に JS が畳む hideOnConnect（rankings/index.html.erb:20）。
  - ほかの書き方：
    - `<noscript><style>`（_header.html.erb:87）
    - noscript の送信ボタン（words/index.html.erb:117）
    - `data-js-only`（row_select:27-28、candidates.css:863）
    - `<noscript><p>`（_genre_sunburst.html.erb:31）
- 提案:
  - J-02 の地図に正典を明記する：サーバは全部描き、JS が畳む（hideOnConnect）／表示する（data-js-only）。
  - stats を移行する案は HTML が変わるので計画書への提案のみ。
- リスク: 低 ／ 外部振る舞いへの影響: 文書だけならなし
- 先に必要な特性テスト: rankings は rankings_controller_test.rb:26 で固定済み。stats は未固定。

### [J-16] DOM の生成と、テンプレートの置換記号が4流儀ある
- 観点: B ／ 確度: 確認済み
- 根拠:
  - `<template>`＋`NEW_RECORD` 系の置換（nested_form:22、word_requests/new.html.erb:39-43、_sense_fields.html.erb:204-208,239-243）
  - `<template>`＋`__ID__/__NAME__` の置換（inline_add:69-71）
  - outerHTML を `"[word_senses_attributes]["` で分割・結合（sense_cloner:16-19。Rails の nested attributes の命名に依存）
  - createElement（genre_picker:115-141、feature_range:69-79、genre_sunburst:240-251）
  - 新しい添字は `Date.now()`（nested_form:22、sense_cloner:17）
- 提案:
  - 正典は「サーバ側のマークアップを `<template>` target に置き、置換記号は nested_form の placeholder の値で指定する方式」。
  - createElement はクライアント専用の図に限る。
  - sense_cloner が Rails の命名に依存していることをコメントで明記する。
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要（文書化のみ）

### [J-17] clipboard：2秒以内に2回押すと「コピーしました」のまま戻らない
- 観点: E（バグ） ／ 確度: 確認済み（コードを読んで確認）
- 根拠: clipboard_controller.js:21 が押すたびに `original = labelTarget.textContent` を取り直し、:23 で前のタイマーを消す。2回目は完了文言を「元の文言」として保存してしまい、それに戻す。
- 提案: 元の文言は connect で1度だけ保持する。
- 影響ファイル: clipboard_controller.js（公開の words/show と管理画面4箇所）
- リスク: 低 ／ 外部振る舞いへの影響: あり（公開ページのボタン表示が正しく戻るようになる。計画書で明示すること）
- 先に必要な特性テスト: 無い（words_controller_test.rb:262 は data-action だけを見ている）ので、system test を先に追加する。

### [J-18] 小さな誤り・不足のあるコメント（名前と振る舞いのずれ）
- 観点: A ／ 確度: 確認済み
- 根拠:
  - char_type:4 はキーを「あ・ア・漢・A・@」の5個と書くが、実際は1と a を含む7個（searches/index.html.erb:119-121）。
  - auto_submit:3「親フォームを送信」→ 実際は :7 で `this.element.requestSubmit()`。付けた要素自身が form でないと動かない。
  - check_all:4「Issue 37 の一括アノテーション用」→ admin/word_requests/index.html.erb:27 でも使っている。
  - queue_nav:3-5 はショートカットにしか触れていない。接続するたびに行う `scrollToTop()`（:12-14）は名前からも読めない。
  - test/application_system_test_case.rb の2つのコメントが古い：
    - 「Google Fonts を読み込ませない」→ app に googleapis の参照は無い。
    - 「sticky ヘッダー」→ sticky なのは下端のバー（annotate.css:206、candidates.css:757）で、ヘッダーではない。
- 提案: 上記のコメントを現状に合わせて直す。
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要

### [J-19] 未使用のもの・テスト専用なのに JS 用の名前を持つもの
- 観点: C・A ／ 確度: 確認済み
- 検索したパターン：`escapeHtml`・`js-feature`・`js-genre-(large|medium|small)` を app/ と test/ で全文検索。
- 根拠:
  - `export function escapeHtml`（inline_add:128）は、同じファイルの :71 でしか使われていない。
  - `.js-feature`（_feature_fields.html.erb:4）はどこからも参照されていない。
  - `.js-genre-large/medium/small`（_sense_fields.html.erb:95,103,107 と _bulk_annotation.html.erb:22,30,34）は JS から使われず、system test（admin_annotation_console_test.rb:173,182,183,197,205）だけが使う。
  - char_type_toggle は2つとも `changed` を発火するが、受け手があるのは1つ目だけ（searches/index.html.erb:144）。害は無い。
- 提案:
  - escapeHtml の export を外す。`.js-feature` は削除する。
  - `js-genre-*` はテストの期待値に関わるので名前は変えず、「テスト用のフック」とコメントで明記する。
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要

### [J-20] Plotly の遅延読み込みは3つの前提の上に成り立っており、importmap audit の対象にもなっていない
- 観点: E ／ 確度: 確認済み（audit の対象外であることは推測）
- 根拠:
  - genre_sunburst:62-75 が `<script src>` を head に挿入し、UMD が定義する `window.Plotly` を使う。
  - URL は `asset_path("plotly.min.js")`（stats/_genre_sunburst.html.erb:5）。配信は app/assets/config/manifest.js の `//= link_tree ../../../vendor/javascript .js` に依存する。
  - importmap にはピンが無い。同梱の版は plotly.js v2.35.2。
- 問題: 次のどれをやっても壊れる。
  - 「vendor/javascript にあるならピンすべき」と考えてピンする（4.5MB を ES module として扱い、window.Plotly が定義されない）。
  - manifest の link を消す。
  - CSP を導入する。
  - また、CLAUDE.md が必須にしている `bin/importmap audit` はピンだけを見るので、唯一のサードパーティ JS の脆弱性確認が漏れる。
- 提案: importmap.rb・manifest.js・overview §2 に「意図的にピンしない」ことと、版・更新時の確認手順を書く。
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: stats_controller_test.rb:29-35 は枠とデータだけを固定している。描画を確かめる system test は任意。

---

## まとめ1. この領域の正典パターン案
- **冒頭コメント**：目的・使う画面・JS が無いとどうなるか・連携するイベントを書く。手本は decision_list_controller.js:6-17、row_select_controller.js:11-20、panel_switch_controller.js:3-9。
- **Ruby の値や文言の受け渡し**：ヘルパで data ハッシュを組み、定数と t() を渡す。手本は word_requests_helper.rb:4-13 と word_candidates_helper.rb:17-38。JS に日本語や基準値を直書きしない。プレースホルダは `%{name}`。
- **大域イベント**：data-action の `@window`／`@document` で受ける。手本は _header.html.erb:42 と word_candidates_helper.rb:8-13。addEventListener は matchMedia などに限り、disconnect で外す（theme_controller.js:13-21）。
- **Turbo キャッシュ**：開閉状態を持つ部品は before-cache で閉じる。手本は nav_menu_controller.js:8-16（data-action で書くことを推奨）。
- **タイマー**：disconnect で必ず clear する。手本は char_type_toggle_controller.js:35-41。
- **コントローラ間の連携**：`this.dispatch()` と受け手の data-action で結ぶ。手本は sense_completeness:18 と _sense_fields.html.erb:17-19。document 全体に流すのは `theme:change` だけにする。
- **DOM 生成**：サーバ側のマークアップを `<template>` target に置き、置換記号は placeholder の値で指定する。手本は nested_form_controller.js:9-12,22 と word_requests/new.html.erb:39-43。
- **fetch**：`post()` を1本だけ使う（inline_add_controller.js:106-126。CSRF・セッション切れ・JSON 以外の応答を扱う）。サーバ側の対は InlineMasterCreatable。失敗は必ず表示する。共通関数は controllers/support/ に置く。
- **キーボード**：モジュール定数 EDITABLE＋closest＋isComposing で判定する（decision_list:3-4,73-75）。共有モジュール化して1つにする。
- **localStorage**：try/catch を付ける。手本は theme_controller.js:48-55。
- **段階的な強化**：サーバは全部描き、JS が畳む・表示する。手本は rankings/index.html.erb:20（hideOnConnect）と candidates.css:863（data-js-only）。
- **要素ごとの引数**：action params を使う。手本は searches/index.html.erb:125。

## まとめ2. コードに表明すべき暗黙の前提
1. コントローラは遅延読み込みされ、最初の描画の時点ではまだ接続していない。system test は wait_for_stimulus が必須で、そのために `window.Stimulus` が要る（controllers/application.js:7）。
2. 識別子とファイル名は `-`↔`_`、`--`↔`/` で対応する。controllers/ 配下でも `_controller` 以外は自動登録されない（推測）。
3. Plotly はピンせず、Sprockets で配信し、UMD の global として使う（J-20）。
4. CSP は未設定で、`nonce: true` は効いていない（J-11）。
5. 削除済みの行は「display:none＋_destroy=1」で表し、サーバ側の描画も同じ表現を使う。完了は `is-complete` クラスで表し、付けるのは sense_completeness だけ。
6. sense_cloner は Rails の nested attributes の名前 `[word_senses_attributes][i]` に依存する。新しい添字の `Date.now()` は、1ミリ秒に2回追加しないことが前提。
7. deck の recount はクリックのバブリング順に依存する（_deck.html.erb:7）。
8. 挿入直後の要素の data-action は遅れて結ばれる（genre_picker:188-190）。
9. セッションが切れると、200 番でログイン画面の HTML が返る（inline_add:119）。
10. 読みのカタカナ規則はクライアントにしか無い。
11. 文字数はコードポイントで数える。ただし JS の trim は全角空白も落とす。
12. 値の持ち主：母音遷移の形式は WordSenseSearch::VOWEL_TRANSITION_FORMAT、文字種の記号は CharTypePattern、候補画面のキーは CANDIDATE_DECISION_KEYS。
13. テーマのキー "theme" と theme-color の読み方は2箇所にある。
14. タッチ端末の判定に `(hover: none)` を使っている（decision_list:162）。
15. queue_nav は Turbo Frame が差し替わるたびに接続し直し、ページ先頭へスクロールする。

## まとめ3. コメントの傾向
- 全体として「なぜ」を書くコメントが多く、質は高い。オーナー指示の日付も残っている（vowel_graph:9 など）。
- 「何をしているか」だけのコメントは、JS のコメント約300行のうち30行程度（1割前後）。代表例：
  - sense_cloner:32「クリアする項目: 読み・意味。」、:34「エンティティは「指定なし」へ。」、:37「別表記は空に。」
  - feature_range:85-87 の行末「新しく始点」「終点確定」「始点を前へ」
  - reading_format:12「入力のたびに、その行だけを検証する。」
  - genre_sunburst の区切り見出し（:91「--- データ参照 ---」など）
- より大きな問題は「現状とずれたコメント」のほう。冒頭コメントは28本すべてにあるが、そのうち6本（auto_submit, char_type, check_all, feature_range, nav_drawer, queue_nav）がずれている。本文にも誤ったコメントがある（range_slider:42、genre_sunburst:38）。

---

## 未確認のまま残した範囲
- ブラウザでの再現は一切していない：J-03（特徴行の復活）、J-09（「戻る」でドロワーが開く）、J-10（ボタン上の Enter）、J-06d（全角空白での1字ずれ）。
- `bin/importmap audit` の実際の対象範囲（実行していない）。
- gem 同梱の stimulus-loading の実装は読んでいない。識別子とファイル名の対応、support/ に置いても安全かどうかは一般的な仕様からの推測。
- SiteStatistics::DISTRIBUTION_OVERFLOW_MIN の値（30 の持ち主の候補かどうか）。
- 通読していないビュー：admin/candidates/_word.html.erb、admin/word_candidates/edit.html.erb、admin/candidates/lists/show.html.erb の全体、searches/_kana_grid・_check_chips（data-controller が無いことだけ grep で確認）、admin/annotations/_proposal*。
- test/integration・test/helpers が固定している data 属性（確認したのは test/controllers の grep 結果だけ）。
- docs/issues.md・changelog.md の JS 関連の確定事項との照合（照合したのは overview・design・stats だけ）。
- ドロワーとキャレット以外の CSS の reduced-motion 対応の全体。

## 棚卸し（ce74da5）

- 前提: `git diff a04f375..ce74da5 -- app config lib db test vendor` は空。行番号はそのまま使える。
- **陳腐化: 0 件。**
- **重複**（計画書 §9 で同じ改修項目に束ねてある）:
  - J-07 ↔ C-17（スライダーの境界値の直書き。C3-20）
  - J-19 ↔ M-15・C-16（未使用。R2-03）
- **要確認**: J-06d（全角空白での 1 字ずれ）、J-09（「戻る」でドロワーが開いたまま）、J-10（ボタン上の Enter）。
  いずれも計画書では §7.1（振る舞いの変更）に回してあり、この改修では直さない。ブラウザでの再現も、この改修ではしない。
- **未確認の範囲のうち、この棚卸しで決着したもの**:
  - `SiteStatistics::DISTRIBUTION_OVERFLOW_MIN` の値: `app/models/site_statistics.rb:147` で `30`。J-07 の提案どおり、スライダーの上限の持ち主にできる。
  - J-20 の「Plotly は importmap audit の対象外」: `config/importmap.rb` に Plotly の pin は無い（`genre_sunburst_controller.js:9` が `vendor/javascript/plotly.min.js` を自前で読む）。**推測から確認済みに格上げ**。
  - stimulus-loading の識別子とファイル名の対応: 計画書 §2 で統合担当が確認済み（`_controller` で終わるファイルだけを登録する）。
  - B-02 から預かった「Stimulus の controller 名と JS の対応」: この記録の冒頭の一覧（全コントローラ・使用箇所・テスト）で覆われている。
- **ほかの単位に任せるもの**:
  - 未通読のビュー（admin/candidates/_word・admin/word_candidates/edit・lists/show・annotations/_proposal*）は A-04 に含まれる。searches/_kana_grid・_check_chips は data-controller が無いことを確認済みなので見ない。
  - test/integration・test/helpers が固定している data 属性は B-06。
  - issues.md・changelog.md との照合は B-08。
  - CSS の reduced-motion 対応は B-04。
- A-01 の JS 側: この記録は feature_range の target_start の計算を扱っていない（J-06 は別の規則）。A-01 に残す。
