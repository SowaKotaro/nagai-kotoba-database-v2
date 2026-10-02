> フェーズ1の監査報告（担当: app/assets/stylesheets）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# 監査報告（担当: app/assets/stylesheets ほか ／ ID プレフィクス S-）

対象: tokens / base / layout / components / annotate / candidates / admin / application.css（計 9,285 行、クラス名 825 種）、manifest.js、config/initializers/assets.rb、レイアウトの stylesheet_link_tag、test/assets/design_tokens_test.rb。コードは一切変更していません。コーディネーターの指示どおり、他担当が報告済みの項目は重ねていません（`--bg` の役割と面3段、章の罫5箇所、admin.css がコンポーネントも上書きする件、design.md の古い級数・行間・10px、components.css の古いコメント（.label-en 白抜き・.home-column・.word-flavor・.prose・「アクセント」表記））。

**先に、確認して問題が無かった点**: ダークの二重定義（`@media` 側と `[data-theme]` 側）は23宣言まで一致している。`var(--x)` の参照先が定義されていないものは無い。`.is-admin *` の全称セレクタは無い。font-weight は 400 / 500（b, strong）/ 700（.figure-number）だけ。ヘッダーは sticky ではない。base の `:focus-visible` は消されていない。.figure-number の `@supports` フォールバックはある。`[hidden]` の打ち消しは全ファイルで同じ書き方。

---

### [S-01] 管理画面のトークン上書きがダークモードを打ち消している（design.md §9.4 と矛盾）
- 観点: A・E ／ 確度: 確認済み（カスケードの読解と値の計算による。画面での目視はしていない）
- 根拠:
  - admin.css:25-30 `.is-admin { --text-muted: #414850; --text-subtle: #4a515a; --border: #c4cad3; --border-strong: #98a1ad; }`。ライトの固定値で、admin.css・candidates.css・annotate.css のどこにも `prefers-color-scheme` / `data-theme` の分岐が無い。
  - `.is-admin` は `<body>` に付く（application.html.erb:90）。ダークの値は `:root` 側（tokens.css:128-182）に入るので、body の上書きが勝つ。
  - design.md:595「公開側・管理画面・アノテーションコンソールの**すべてに適用**」。ヘッダーのトグルは管理画面にも出ている（layout 94 行で shared/header を常に描画）。
  - ダーク時の計算値: `--text-muted` #414850 を面 #232930 に載せて約 1.6:1、`--text-subtle` 約 1.8:1、`--admin-accent` #1d4ed8 約 2.2:1。`--admin-accent` と `--admin-warn` にはダークの値が無い（admin.css:98-101）。
  - candidates.css:702/707/712 の `color: #fff` は、ダークの `--danger`（#d98079）の上で約 2.9:1 になる。
- 問題: design.md を読んだエージェントは「管理画面もダーク対応済み」と判断するが、実際は補足文字がほぼ読めず、罫だけ明るく光る。design_tokens_test は tokens.css しか測っていないので気づけない。
- 提案（**計画書への提案のみ**。ダーク時の管理画面の見た目が変わる）: まず、管理画面をダークに対応させるのか、ライトに固定するのかをオーナーに確認する。対応させるなら、tokens.css と同じ型（`--dark-admin-*` の値 ＋ 2つの適用ブロック）で admin.css に書く。固定するなら、`.is-admin` で `color-scheme: light` にし、トグルを隠す。
- 影響ファイル: admin.css, candidates.css, tokens.css, docs/design.md §9.4・§10
- リスク: 中 ／ 外部振る舞いへの影響: あり（管理画面のダーク表示。公開側は変わらない）
- 先に必要な特性テスト: design_tokens_test.rb の型で「admin.css の上書き値 × ライトとダークの面」のコントラストを測るテスト（現状の不足を明示する目的で pending にしておく）

### [S-02] CSS の置き場所（層の分担）が、docs とファイル冒頭の説明どおりになっていない
- 観点: A・D ／ 確度: 確認済み（ただし行数は節見出しからの概算で、推測）
- 根拠:
  - application.css:6-13 は `tokens → base → layout → components → annotate → candidates → admin → self` の順。docs/overview.md:39 と :143 は「＋ admin.css / annotate.css」とだけ書き、**candidates.css が抜けている**。
  - レイアウトは application.html.erb 1 本だけ（:58 `stylesheet_link_tag "application"`）。このため**管理画面専用の annotate・candidates・admin も公開ページ全部で読まれている**。
  - base.css:1「素のタグへの基本設定」と書いてあるのに、クラスの `.mono` がある（base.css:97-102）。
  - layout.css にコンポーネントが入っている: `.skip-link` 265-290、`.nav-menu` 190-263、`.theme-toggle` 621-683、`.flash` 685-710、管理画面の `.admin-nav` と `.admin-nav__badge` 473-519。
  - components.css には管理画面専用の部品がおよそ1,100行ある（2324-2744 の admin-card・admin-words・bulk-annotation・proposal、3050-3493 の一括登録、3536-3683 のタグ、5137-5260 のリクエスト）。
  - annotate.css:226-240 の `.bulk-approval` はコンソールではなく bulk_proposal_approvals/show.html.erb 用。
  - candidates.css は admin.css だけが定義する `--admin-accent` / `--admin-warn` を25回参照している（admin.css 側の参照は10回）。
  - manifest.js:2 `link_directory ../stylesheets .css` によって、各 CSS 単体も個別の資産として公開されている（読み込んでいるのは application だけ）。
- 問題: 管理画面の部品を探すと4ファイル（layout・components・annotate・candidates）に admin.css を足した計5箇所を見ることになる。「tokens→base→layout→components」を信じて足した規則は置き場所を誤りやすく、順序依存（S-03）も踏みやすい。
- 提案: ①最初にゼロリスクの修正として、実際の配置の地図を docs/overview.md §2・§6 と application.css の冒頭コメントに書く（candidates.css の役割、admin 系の読み込み順が意味すること、全ページで読まれること）。あわせて base.css の冒頭を「素のタグ＋全体で使うユーティリティ（`.mono`）」に直す。②ファイル間の移動は、見た目の同一性を確かめる手段を先に用意してから行う（S-03 の順序依存を壊すため）。移動しても順序が変わらない末尾の塊（components.css 5137-5260 など）から始める。③管理画面用の CSS を公開ページから外す案（レイアウトの分岐）は**計画書への提案のみ**。
- 影響ファイル: application.css, docs/overview.md, base.css, layout.css, components.css, annotate.css, candidates.css
- リスク: ①低 ②中 ③中 ／ 外部振る舞いへの影響: ①②なし、③あり（配信する CSS が変わる）
- 先に必要な特性テスト: application.css の require の並びを固定するテスト。移動の前後で、代表ページの主要要素の `getComputedStyle` を比べる（使い捨てのスクリプトでよい）

### [S-03] 後勝ち（読み込み順・記述順）に頼った上書きと重複定義
- 観点: B・E ／ 確度: 確認済み（どちらが勝つかはカスケードで確認した。意図は推測）
- 根拠:
  - `.section-heading` が2回定義されている: components.css:655-661（`margin: 0 0 var(--space-4)`＋下罫）と 2746-2750（`margin: var(--space-7) 0 var(--space-4)`）。margin は後の定義が勝つ。
  - `.stats-grid--rows { gap: 2px }`（1988）を、約330行後の `@media (max-width: 767px) { .stats-grid { gap: var(--space-2) var(--space-4) } }`（2318-2321）が同じ特異度で上書きしている。767px 以下では、ホームの数の行間が 8px になる。`.stats-grid` の基本の `margin: var(--space-7) 0 0`（1859）は、実際の使用2箇所（`--rows` 1989 と `.is-admin` admin.css:130）の両方で上書きされていて、どこにも効いていない。
  - 1つの要素に2つのブロックのクラスが付いている箇所: `class="ring-art__caption label-en"`（shared/_kana_ring_art.html.erb:44）で、10px・0.06em は `.ring-art__caption`（2071-2076）が `.label-en`（1896-1909）より後にあることで成り立っている。`class="entry-range mono"`（words/index.html.erb:87）の 11px も、`.entry-range`（components.css:154）が `.mono` の 0.92em（base.css:100）より後にあることで成り立っている。
  - `.admin-words-table__annotated / __unannotated / __on-hold` の色（components.css:2728-2743）は admin.css:233-243 が必ず上書きする。表は管理画面にしか無いため、components.css 側の色は常に効かない（2733 の「未対応はアクセント色」も実態と合わない）。
  - annotate.css:300-301 は「このファイルは components より後に読まれるため」と書き、読み込み順を前提にしている。
- 問題: どの値が効くのかを1箇所読んだだけでは判断できない。並べ替えや移動（S-02）で、黙って見た目が変わる。
- 提案（見た目は変えない）: 重複は後勝ちの結果の値で1つにまとめる（`.section-heading` は margin に space-7 を採る）。media の gap は `.stats-grid--rows` の定義のそばへ移し、効いている対象を明示する（`@media (max-width:767px){ .stats-grid--rows { gap: var(--space-2) var(--space-4) } }` とすれば、ホームの見た目は同じまま admin にも影響しない）。`.stats-grid` の効いていない margin と components.css の admin 表の色は削除する。2つのブロックが重なる要素には「この規則は X より後に置くこと」と両側にコメントする。
- 影響ファイル: components.css, base.css, admin.css
- リスク: 中 ／ 外部振る舞いへの影響: なし（結果の値を保つ前提）
- 先に必要な特性テスト: ホームの 767px 以下での `.stats-grid--rows` の gap、`.section-heading`（/browse）の margin、`.ring-art__caption` の font-size を computed style で固定する

### [S-04] 確度の高い未使用セレクタ
- 観点: C ／ 確度: 確認済み
- 検索したパターン: クラス名の完全一致を PCRE `(?<![\w-])name(?![\w-])` で、app/views・helpers・javascript・models・controllers・services、lib、config/locales、test に対して検索した。BEM の修飾子を文字列で組み立てる箇所も、`"block__el--"` の前方一致と ERB・Ruby の式展開で調べた。そのほか `icon(name, css)` の第2引数、`class_names`、`classList`、i18n の `*_html` も含めた。825 種のうち、どこからも参照が無いのは次のとおり。
- 根拠:
  - `.btn--danger`（admin.css:249, 256）
  - `.field--keyword`（components.css:2945）
  - `.icon--lg`（components.css:15）
  - `.reading-column`（layout.css:469）
  - `.search-switch`（components.css:1851）
  - `.tag--static`（components.css:646。値も `.tag` と同じ）
  - `.word-sense-fields` と `.word-sense-feature-fields`（components.css:3479-3492「管理フォームの入れ子」。編集画面は廃止済み）
  - `.is-admin .proposal`（admin.css:64。`proposal` というクラスは存在しない）
  - `.is-admin .admin-status-tabs .is-current`（admin.css:275。タブは aria-current だけを使う）
  - アイコンの余白の対象から外れている `.page-eyebrow .icon` と `.stats-grid__item dt .icon`（components.css:26, 23。中にアイコンを置く箇所が無い）
  - `.entry-row__go`（components.css:1096-1099。`display:none` なのに、コメントは「押せる行であることだけを示す矢印」。ビュー words/_entry_row.html.erb:31 は今も `icon "arrow_right", "entry-row__go"` を出力している。design.md §5.3 は「矢印などの装飾は置かない」）
  - 宣言の無い孤立コメント5行（components.css:449-453「円環を開く副次的な導線」ほか）
  - テストからしか参照されていないクラスは無い。
- 問題: 削除済みの部品が、使える部品に見える。
- 提案: 削除する（`.entry-row__go` はビュー側の出力と一緒に消す。描画されていないので見た目は変わらない）。
- 影響ファイル: admin.css, components.css, layout.css, words/_entry_row.html.erb
- リスク: 低 ／ 外部振る舞いへの影響: なし（`.entry-row__go` を外すと HTML から非表示の svg が1つ消えるが、aria-hidden の装飾なので意味構造は変わらない）
- 先に必要な特性テスト: 不要（既存の assert_select は上記を参照していない）

### [S-05] 効いていない宣言・効かない指定
- 観点: C ／ 確度: 確認済み（font-weight は代表例のみ確認）
- 根拠:
  - admin.css:62-67 の `box-shadow: none` の規則全体。`.admin-card` と `.sense-card` にはもともと影が無く、`.nav-menu__panel` の `--shadow-pop` は admin.css:41 で既に none になっている。
  - annotate.css:113 `.ann-sense.is-complete { border-color: var(--success) }`。`.ann-sense`（109）に枠が無いので効かない。コメント 110-112 の「枠を緑に替え」も実態と違う。
  - components.css:611 `border-bottom: 0`（打ち消す相手が無い）。
  - candidates.css:355 の `margin-left: auto` を、同じ規則の 359 `margin: 0` が打ち消している。
  - candidates.css:1077-1079（基本と同じ値の繰り返し）。
  - annotate.css:139 `border: none` の直後に 140 で `border: 1px …`。
  - hover の色が通常時と同じ: components.css:2228-2230、annotate.css:166。
  - `font-weight: 400` が49箇所（components 30 / annotate 16 / candidates 1 / base 2）。多くは `<a>`・`<span>`・`<li>` などへの指定で効いていない（例: components.css:586 `a.genre-path__current`、2532 のタブの `<a>`、5210 の `<span>`）。太字を使っていた時代の名残。
- 問題: 「ここに枠がある」「ここは太字を打ち消す必要がある」と誤読される。
- 提案: 削除する。font-weight は要素を確かめてから削る。th・b・strong・h1〜h6・legend に掛かるもの（例: annotate.css:19 の `b`、4916 の `th`）は残す。
- 影響ファイル: admin.css, annotate.css, candidates.css, components.css
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要。font-weight を削る場合は、対象要素の computed の font-weight を記録してから削る

### [S-06] 同じ見た目を別々に定義している部品群
- 観点: B ／ 確度: 確認済み
- 根拠と正典案:
  - 丸タグ: `.chip`（components.css:492-510）と `.tag`（626-643）は、`.chip` の `margin-bottom:4px` 以外がほぼ同じ。**正典は `.tag`** とし、`.chip` はセレクタを並べて共有する（`.tag, .chip {…}`）。
  - 「一覧へ →」の導線: `.home-column__more`（2171-2183）と `.home-featured__more`（2298-2310）は同じ内容で、`.related__more`（783-790）もほぼ同じ。
  - 白地に白い面（見えない囲い）: `border-radius: var(--radius-lg); background: var(--surface); padding: …` がそのまま8回出てくる。`.fieldset-card` 2951、`.bulk-annotation` 2543、`.bulk-result` 3068、`.bulk-research` 3272、`.tag-add` 3552、`.tag-merge` 3582、`.bulk-requests` 5226、annotate.css:109 `.ann-sense`。いずれも白い本文の上にあるので輪郭が出ていない。そのうえコメントは「細罫の角丸パネル」（2950）、「パネルは細罫の角丸」（2542）と書いている。`__summary` の4つ（2550 / 3279 / 3558 / 3588）も同じ内容。
  - 赤い枠のエラー: `.flash--alert`（layout.css:702-706）、`.form-alert`（3058）、`.error-explanation`（3094）、`.form-errors`（3538）、`.dup-note--exact / --similar`（4993）。**正典は `.form-alert`**。
  - 視覚的に隠す指定: `.visually-hidden`（1264-1274）、`.skip-link:not(:focus)`（layout.css:268。コメントには「.visually-hidden と同じ方法」とある）、`.request-table__label`（4964。clip-path を使う別方式）。
  - キー表示: 非標準の `<key>` 要素（annotate.css:22 と admin/annotations/show.html.erb:10-12）、`kbd`（candidates.css:364）、`.kbd`（annotate.css:213）、`.cand-bar__kbd`（872）、`.cand-choice__key`（722）。
  - フォーカスの輪: base は `--text-muted` 2px・offset 2（base.css:64-68）。一方で `--text` 2px・offset 1 がある（components.css:1689, 1730, 1464, 2992）。offset 2 のもの（annotate.css:149）、1px のもの（4571）、-2px のもの（2372）もある。
  - 下線タブ: `.admin-status-tabs__tab`（components.css:2518）と `.cand-status-tabs__tab`（candidates.css:948）。
  - 表: `.data-table`、`.bulk-review__table`、`.request-table`、`.bulk-approval`（annotate.css:227）、`.cand-table` の5系統。
- 問題: 手本が一意に決まらず、新しい部品が6つ目の書き方で増える。
- 提案: 見た目が完全に同じ組は、セレクタを並べて1つの規則にまとめる（見た目は変わらない）。値が少しずつ違う組（フォーカスの輪・タブ・表・キー表示）は、揃えると見た目が変わるので**計画書への提案のみ**。`<key>` を `<kbd>` へ置き換える件は UA スタイルの差を確かめる必要があるので計画書へ。見えない囲いは「残す（将来 `--bg-soft` にする）か、外すか」をオーナーに確認する。外しても見た目は変わらない。
- 影響ファイル: components.css, layout.css, annotate.css, candidates.css, 管理画面のビュー
- リスク: 低〜中 ／ 外部振る舞いへの影響: まとめるだけならなし
- 先に必要な特性テスト: `.tag` と `.chip`、「一覧へ」の導線の computed style を固定する

### [S-07] トークン: 未使用・出どころ・admin で逆転するスケール・直書き
- 観点: C・D・E ／ 確度: 確認済み
- 根拠:
  - `--shadow-soft` は tokens.css:48・120・151・179 と admin.css:40 で定義されているが、`var(--shadow-soft)` を参照する箇所は CSS・ビュー・JS のどこにも無い（未使用）。design.md:213 と :573 は使っている前提で書いている。
  - `--admin-accent` と `--admin-warn` は admin.css:98-101 の `.is-admin` の中だけで定義されており、`.is-admin` の定義ブロックも 17-44 と 98-101 の2つに分かれている。
  - admin では `--radius` が 3px（admin.css:35）になるのに、`--radius-sm` は 6px のまま（tokens.css:82）。**小さいはずの角丸のほうが大きく**なる。candidates.css は `border-radius: 3px` を4回直書きしている（252, 368, 542, 599）。色の直書きは `#fff` が4回（562, 702, 707, 712）。
  - tokens.css:1 は「色・フォント・余白はここ以外で直書きしない」と書くが、実際には余白の px 直書きが約320箇所ある（うち約82箇所はトークンと同じ値。例: layout.css:105 `padding: 12px`、components.css:177 `gap: 8px`、3669 `margin: 12px 0 20px`）。級数は19種類の値で約380箇所、行間は18種類。級数と行間にはそもそもトークンが無い。
  - transition の直書きは11箇所（layout.css:124, 216, 736、components.css:1444, 1483, 1776, 3000, 4015, 4297, 4622）。
  - 未定義のトークンへの参照は無い。インラインで設定されるローカル変数には、どれも設定元がある。`--fill`（browse・stats）、`--w`（genres・stats）、`--from` / `--to`（range_slider_controller.js:47-48）、`--meter`（dashboard:29）、`--ring-length` / `--ring-center`（_kana_ring_art:15）、`--chart-width`（_length_chart:12）。
- 問題: 「直書き禁止」を信じて既存の値を機械的にトークンへ置き換えると見た目が変わる（直書きの大半はトークンと値が違う）。逆に、直書きしてよい範囲も分からない。
- 提案: tokens.css:1 を実際の方針に書き直す（色は厳格にトークン、余白は区画のリズムにトークン、部品内の微調整の px と級数・行間は直書きを許す、級数の正は design.md §2）。`--shadow-soft` は削除するか、用途を決める。`.is-admin` のトークンは1ブロックにまとめる（見た目は変わらない）。`--radius-sm` の扱い（admin で上書きするか）は**計画書への提案のみ**。トークンと同じ値の直書きは var() に置き換える（見た目は変わらない）。
- 影響ファイル: tokens.css, admin.css, candidates.css, components.css, layout.css, annotate.css, docs/design.md §3・§9.1
- リスク: 低 ／ 外部振る舞いへの影響: なし（`--radius-sm` を除く）
- 先に必要な特性テスト: 「CSS 中の var(--x) はすべて tokens.css・admin.css の定義か、既知のローカル変数一覧に解決する」ことを確かめる静的テスト

### [S-08] ダークの二重定義は一致しているが、手作業でしか守られていない。CSS 以外にあるトークンの写し
- 観点: D・E ／ 確度: 確認済み
- 根拠:
  - tokens.css:128-155 と 157-182 の宣言は一致している。守っているのは tokens.css:127 のコメント「※トークンを 1 つ足したら、下の 2 ブロック両方に参照を追記すること」だけ。design_tokens_test.rb:10-21 は `--x` と `--dark-x` の値を測るが、2ブロックの一致は見ていない。
  - CSS の外に写しがある:
    - genre_sunburst_controller.js:16-19 は `--chart` のライトの値から作ったパレット（`"#6F8EA8", "#829DB4", …`）を直書きしている。同じファイルの :38「グラフの色は JS に持たせず CSS のトークンから読む」とも、design.md §9.2 とも矛盾する。
    - theme-color を `--bg` から読む処理が2箇所にある（application.html.erb:73-77 と theme_controller.js:39-43）。application.html.erb:54-56 のコメントは「既定値はライトの --bg」だが、実際の値は `content="#ffffff"`（--bg は #eff2f6）。
    - share_cards/word.svg.erb:4 と public/icon.svg の色の写しはコメントに明記されているが、ずれを検出する手段が無い。
- 提案: 2ブロックの一致を確かめるテストを足す（見た目は変わらない）。theme-color の既定値のコメントを直す。Plotly のパレットをトークンから作る件は**計画書への提案のみ**（ダーク時のグラフの色が変わる）。
- 影響ファイル: tokens.css, test/assets/design_tokens_test.rb, application.html.erb, theme_controller.js, genre_sunburst_controller.js
- リスク: 低 ／ 外部振る舞いへの影響: なし（パレットの件を除く）
- 先に必要な特性テスト: 上記の一致テストそのもの

### [S-09] 「管理画面かどうか」の判定が2通りあり、どちらのトーンを当てるかがパスで決まっている
- 観点: D・E ／ 確度: 確認済み（ルートまで含めて2つの判定が同じ結果になるかは推測）
- 根拠: application.html.erb:90 `class="<%= "is-admin" if request.path.start_with?("/admin") %>"`。一方、共通ナビは admin_helper.rb:8-10 `controller.is_a?(Admin::BaseController)` で判定している。ヘッダーの現在地も _header.html.erb:71 でパスを見ている。
- 問題: admin.css が効くかどうかと、管理ナビが出るかどうかが、別の規則で決まっている。
- 提案: 判定を `admin_page?` に一本化する。先に `bin/rails routes` で、/admin 配下が Admin::BaseController 系だけであることを確かめる。
- 影響ファイル: application.html.erb, _header.html.erb, admin_helper.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし（2つの判定が同じ結果になる前提）
- 先に必要な特性テスト: 管理画面の1ページで body に is-admin が付き、公開ページとログイン画面では付かないことを確かめる結合テスト

### [S-10] CSS のクラス名が i18n とビューの中に隠れている
- 観点: E ／ 確度: 確認済み
- 根拠: ja.yml:373-375 `<span class="shiritori__char">`（CSS は components.css:797）、ja.yml:571-572 `<span class="cand-export__num">`（CSS は candidates.css:237）。ビューだけを grep すると未使用に見える。ほかに、_header.html.erb:87 に `<noscript><style>.theme-toggle { display: none; }</style></noscript>` があり、stylesheets の外に CSS がある。
- 提案: CSS 側の該当規則に「使用元: ja.yml の words.show.shiritori.*_html」とコメントする（最小）。
- 影響ファイル: components.css, candidates.css
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 既存の words_controller_test.rb:323 が `.shiritori__char` を固定済み

### [S-11] 公開側の CSS に残る design.md 規則からの逸脱（計画書への提案のみ）
- 観点: A ／ 確度: 確認済み
- 根拠:
  - components.css:1804 `.genre-fold--medium { border-left: 2px solid … }`。design.md §3 は「2px 以上の罫は引かない」。
  - components.css:2443 `box-shadow: 0 0 0 3px var(--bg-tint)`。design.md §4 は「リング（box-shadow）は付けない」（管理画面の検索欄）。
  - 動きの扱い: design.md は「hover の 160ms だけ」「reduced-motion では完成形」と書くが、ドロワーの 0.2s（layout.css:736）、ハンバーガー（124）、キャレット（216, 1776, 3000）は `prefers-reduced-motion` の対象外。reduced-motion の分岐は 1490 と 2102 の2つしかない。
  - `.ring-art__stroke { stroke-width: 1.2 }`（components.css:2058）に対し、design.md §5.9 は「線は 1px」。
  - `.hero__title { font-size: 26px }`（1163）に対し、design.md §2 は24px（他担当の級数の指摘と同じ原因）。
  - 767px 以下の「フォーム部品は16px」の列挙（3688-3704）から漏れがある。`.cand-intake__text` と `.cand-import__text`（candidates.css:153-159、13px のクラス指定が要素セレクタの 16px に勝つ）と `.admin-words-tag-filter select`（2495）が対象外。
- 提案: どれも見た目が変わるので**計画書への提案のみ**。どちらが正しいかをオーナーに確認し、正しい側に docs かコードを合わせる。
- 影響ファイル: components.css, layout.css, candidates.css, docs/design.md
- リスク: 中 ／ 外部振る舞いへの影響: あり（見た目）
- 先に必要な特性テスト: 変更するならその時点で決める

### [S-12] コメントや docs が実態と食い違っている（他担当の報告と重ならないもの）
- 観点: A ／ 確度: 確認済み
- 根拠:
  - admin.css:11「transition / animation / 影 / 大きな角丸 … を落とす」は、同じファイルの 55 行「全称セレクタで transition を潰す案は…取りやめた」と矛盾する。admin.css:57「なし 175.1ms」と design.md:695「撤去後 156.4ms」も数字が違う。
  - admin.css:39「公開側でも使っていないが」とあるが、公開側でも layout.css:237 と 729 で `--shadow-pop` を使っている。
  - tokens.css:9「(フッター・hover・画像帯)」の画像帯は撤去済み。tokens.css:19-20「構造は罫ではなく「余白」で作る」は design.md §3「罫は二層で持つ」と逆のことを言っている。
  - base.css:17「ヘッダー(--bg)」だが、実際は layout.css:6-10 のとおり `--bg-soft`。
  - components.css の古いコメント:
    - 366「語義パネル: 枠を持たない、淡い面」→ 実際は 374 の `border` で、面は無い。
    - 1160-1161「左揃えで、右のレールと対にする」→ 実際は中央揃え（2024-2029）。
    - 1963-1964「細い枠でひと区画を囲い」→ 実際は枠が無い。
    - 1911「標識 + 日本語見出しの縦組み」→ ホームでは `__ja` だけ（home/index.html.erb:85-87）。
    - 2247「淡い面の大きな角丸カード」→ 実際は `margin:0` だけ。
    - 4422「最多の1本だけ --chart」→ 4497-4500 で廃止済み。
    - 4754「見出し行は細罫で仕切る」→ 罫が無い。
    - 5207「未着手だけ色を付けて」→ 実際は `--text`。
    - 2787「(検索結果・管理一覧)」→ `.data-table` は管理画面の4ビューだけで使われている。
    - 3687「ヘッダー検索」→ ヘッダーに検索は無い。
  - その他のファイル:
    - annotate.css:3「アクセントは青一色」→ 青は使っていない。
    - layout.css:366「ページを貫く縦の基準線」→ design.md §5.2「罫は区画の中で完結させる」と逆。
    - design.md:495-497 は「components.css のコメントにもそう書いてある…直すのは Issue 84」のままだが、Issue 84 は完了済み（changelog.md:308）で、コメントも修正済み（components.css:2116-2118）。
- 提案: コメントを現在の不変条件だけに書き直す。経緯は docs に任せる。
- 影響ファイル: admin.css, tokens.css, base.css, layout.css, components.css, annotate.css, docs/design.md
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要

### [S-13] design.md の中で矛盾していて、CSS の正解が決まらない箇所
- 観点: A ／ 確度: 確認済み
- 根拠:
  - design.md:215「一覧やリストは区切り線を引かない」は、§3・§5.3 の `gap: 1px` の罫と矛盾する。
  - :362「行は --radius の当たり判定を持ち」は、同じ節の :352「行に角丸を持たせない」と矛盾する。
  - :375「語義ごとに --bg-soft の角丸カード（枠なし）」と :391「1 枠 = --bg-soft の角丸カード」は、:183（`.sense-card` / `.rank-board` は 1px `--border` の囲い）とも CSS とも合わない。
  - :144 と CLAUDE.md:124「ゼロ埋めしない」は、:363 の `001–100`、および words/index.html.erb:87 の `format("%03d", …)` と矛盾する。
- 提案: 実際の実装に合わせて docs を直す。ゼロ埋めは「目盛りの `.entry-range` だけ例外」と明記する。
- 影響ファイル: docs/design.md, CLAUDE.md
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要

---

## 1. この領域の正典パターン案
- **色**: `var(--token)` だけを使う。色を足すときは tokens.css に「ライトの値＋`--dark-*`＋2つの適用ブロック」を書く（手本 tokens.css:95-182）。管理画面の色は admin.css の `.is-admin` 1ブロックに、ダークの値も持たせて書く（S-01）。
- **並んだ要素の罫**: 親に `display:grid; gap:1px; background:var(--border)`、子に面の色を塗る（手本 `.entry-list` / `.entry-row` components.css:966-994、`.rank-list` 4791-4813）。
- **丸タグ**: `.tag`（626-643）。**ボタン**: `.btn` 系（2825-2879）。**エラーの枠**: `.form-alert`（3058-3065）。**視覚的に隠す**: `.visually-hidden`（1264-1274）。
- **選択状態**: `--text` のベタ＋`--bg` の文字＋`--text` の枠（手本 `.check-chip input:checked + .check-chip__face` 1724-1728）。**フォーカス**: base の `:focus-visible`（base.css:64-68）と同じ値にそろえる。
- **UA の [hidden] を打ち消す書き方**: `.x[hidden] { display:none }` に理由のコメントを添える（手本 components.css:1527-1531）。
- **状態から組み立てる修飾子**: `"block__el block__el--<%= enum値 %>"` と書き、CSS 側には enum の出どころをコメントする（手本 admin/word_requests/index.html.erb:78 ＋ components.css:5207-5217）。
- **transition**: `var(--transition)`（手本 components.css:2841）。
- **ファイル冒頭のコメント**: 対象範囲・色の規則・依存するトークンを書く（手本 candidates.css:1-8。ただし `--admin-*` への依存の明記を足す）。

## 2. コードに表明すべき暗黙の前提
1. `--admin-accent` と `--admin-warn` は `body.is-admin` の下にしか無い（admin.css:98-101）。candidates.css（25回参照）は、常に /admin で描画される前提で書かれている。
2. `.is-admin` はパスの前方一致で付く（application.html.erb:90）。コントローラでは判定していない（admin_helper.rb:8-10）。
3. admin の上書きはライトの値に固定されており、ダーク時の管理画面を想定していない（admin.css:17-44）。
4. 読み込み順に依存している箇所: annotate を components より後に（annotate.css:300-301）、`.ring-art__caption` を `.label-en` より後に、`.entry-range` を `.mono` より後に、2つ目の `.section-heading`、767px の `.stats-grid` の gap（S-03）。
5. 管理画面用の CSS は公開ページでも全部読まれる（レイアウトが1本で、application.css が束ねている）。
6. インラインで渡すローカル変数の単位と範囲: `--fill`（0〜1）、`--w` / `--from` / `--to` / `--meter`（%）、`--ring-length`（単位なし）、`--ring-center`（px を view-box の座標として使う）、`--chart-width`（px）。フォールバックは `var(--fill, 0)`、`var(--w, 0%)`、`var(--chart-width, 720px)`。
7. クラス名が i18n にある（ja.yml:373-375, 571-572）。
8. design_tokens_test.rb:26 は、tokens.css の値が行頭の `--name: #hhhhhh` の形で書かれていることを前提にしている（rgb() や var() で書くとテストが落ちる）。
9. ダークの2つの適用ブロックは手作業でそろえている（tokens.css:127）。
10. 767px 以下の16px の列挙は、入力欄を小さくしているクラスをすべて列挙する前提（components.css:3684-3704。漏れについては S-11）。
11. select の矢印の色 `%236e7781` は data URI なので変数にできない（components.css:2906-2921。コメントに明記されている）。
12. 共有カードの SVG、icon.svg、og_default.py、Plotly のパレットは tokens.css のライトの値の写し。

## 3. コメントの傾向
7ファイルでコメントはおよそ520。**大半は日付とオーナー判断を添えて「なぜ」を書いており**、質は高い。問題は2点ある。
- 部位の名前だけのコメント（何をしているか）が、少なくとも約50ある（1行で短いものを機械的に数えた下限。推測）。例: annotate.css:12 `/* 上部ステータス */`、annotate.css:216 `/* 完了画面 */`、candidates.css:278 `/* 取り込み */`、components.css:896 `/* 別表記の一覧 */`、components.css:3494 `/* --- 汎用 --- */`（雑多な置き場になっている）。
- より深刻なのは、**経緯を書いた「なぜ」のコメントが古くなって嘘になっていること**（S-12 に10件以上）。コード内のコメントは現在の不変条件に絞り、経緯は design.md / changelog に寄せる運用を勧める。

---

## 未確認のまま残した範囲
- S-01（管理画面のダークのコントラスト）と S-03（ホームの 767px の行間）を、実際に描画して目視・実測すること。
- `font-weight: 400` の49箇所それぞれが効いていないかの、要素ごとの確認（確認したのは代表例のみ）。
- 複合セレクタ・子孫セレクタが実際の DOM 構造に一致するかの全件確認。S-04 と S-05 に挙げたもの以外は、クラス名が存在するかしか確かめていない。
- 逆方向の確認（ビューや JS が付けるクラスのうち CSS の無いもの。例: `.stats-header`、`.flash--notice`、`.proposal-json`）。
- `bin/rails routes` による、/admin 配下と Admin::BaseController 系が一致しているかの確認（S-09）。
- 16px の列挙から漏れている入力欄の全件洗い出し（S-11 で挙げたのは3件だけ）。
- 既存の system テスト（theme_toggle_test.rb、word_detail_mobile_test.rb、admin_annotation_console_test.rb）が固定している CSS 上の性質の中身。ファイルがあることだけ確認した。
- 余白・級数の直書きの件数は grep による概算（annotate.css は1行に複数の宣言を書いているので、別の方法で数えた）。
- コメントの傾向の件数は、バイト長で判定した近似値。

### Critical Files for Implementation
- app/assets/stylesheets/admin.css
- app/assets/stylesheets/tokens.css
- app/assets/stylesheets/components.css
- app/assets/stylesheets/application.css
- test/assets/design_tokens_test.rb
