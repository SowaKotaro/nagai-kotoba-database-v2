> フェーズ1の監査報告（担当: 仕様・記録系の文書とコメント）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# 監査報告（SPEC 担当：仕様・記録系の文書と、それを参照するコードコメント）

読み取りだけで作業しました。ファイルの作成・変更・削除、git の状態を変える操作、テスト・DB・rake の実行はしていません。所有者の未コミットの作業中の変更（README.md、.claude/commands/expand.md、.claude/skills/word-expansion-research/ 配下）は調べていません。

指摘は重要度の高い順に並べています。上位ほど、将来のエージェントが誤った変更をしかねない食い違いです。

---

### [SPEC-01] growth-strategy.md の「優先順位」と「残タスク」が、確定事項で否決・完了した作業を指示している
- 観点: A ／ 確度: 確認済み
- 根拠:
  - 否決された作業を指示している: growth-strategy.md:122「データの厚み: 言語的特徴の遡及付与(Issue 76)」 ↔ issues.md:494 確定事項37「遡及付与(改善調査 A-1)は行わない」、changelog.md:298（Issue 76 はクローズ）
  - growth-strategy.md:47-48「残っているのは Bing Webmaster Tools の所有権確認と sitemap 送信」 ↔ issues.md:484 確定事項33「Bing Webmaster Tools は当面触らない」
  - 文書内で矛盾: growth-strategy.md:31「解禁予定日を逆算する」 ↔ 同じ文書の :46「インデックス解禁は 2026-07-19 に実施済み」
  - 冒頭 :3 の「現状評価の更新: 2026-09-16」は、確定事項37（2026-09-23）より前の日付
- 問題: 優先順位の表をそのまま信じたエージェントが、オーナーが却下した作業（遡及付与・Bing）に着手します。
- 提案: 正は issues.md の確定事項とします。growth-strategy.md は §0（ポジショニング）と §3（KPI ツリー）だけを現行として残します。「現状評価」と「現フェーズの優先順位」は、日付つきのスナップショットとして docs/history/ へ移すか、確定事項32・33・37 に合わせて書き直します。
- 影響ファイル: docs/growth-strategy.md
- リスク: 高 ／ 外部振る舞いへの影響: なし

### [SPEC-02] ゼロ埋め番号の禁止が「例外なし」と書かれているが、実装と design.md §5.3 は `001–100` を使っている
- 観点: A ／ 確度: 確認済み
- 根拠:
  - 禁止している側: CLAUDE.md:124「`01` 形式のゼロ埋め番号…は使わない」、design.md:52（§0 の禁止事項）、design.md:144「ゼロ埋め（`01`）はしない」
  - 使っている側: design.md:363「`.entry-range`（等幅 11px）で **`001–100`**」、app/views/words/index.html.erb:87 `format("%03d", first_index)`、components.css:153 のコメント「(001–050)」
- 問題: CLAUDE.md を守るエージェントは公開 HTML から 0 埋めを外してしまいます。逆に §5.3 を根拠に、順位や語義番号へ 0 埋めを広げる恐れもあります。
- 提案: 現在の実装を正とします。design.md §2 と CLAUDE.md に「一覧の目盛り `.entry-range` だけは 3 桁で埋める。順位・語義番号には使わない」という例外を 1 行で明記します。
- 影響ファイル: CLAUDE.md, docs/design.md, app/assets/stylesheets/components.css（コメントの 050 を 100 に）
- リスク: 中 ／ 外部振る舞いへの影響: なし（文書だけの修正）

### [SPEC-03] `--bg` の役割と「面は 3 段」の説明が、文書間でも実装とも食い違っている
- 観点: A ／ 確度: 確認済み
- 根拠（文書側）:
  - CLAUDE.md:159-160「`--bg`（ボタンの塗り）」
  - design.md:170「`--bg` | ボタン・タグの塗り」
  - design.md:79「`--bg` 地。すべての立体の基準面」と :80「`--surface` …ボタン・タグ・入力」は、同じ文書の中で互いに矛盾
  - tokens.css:8「--bg 地(ページの背景)」、tokens.css:9「--bg-soft …画像帯」（画像帯は撤去済み）
  - base.css:17「色を持つのはヘッダー(--bg)とフッター(--bg-soft)だけ」
- 根拠（実物）:
  - base.css:22 で `body` の背景は `var(--surface)`
  - layout.css:6-9 で `.site-header` は `var(--bg-soft)`。コメントにも「--bg だと ΔRGB 16 で下限に届かなかった」とある
  - `.btn` / `.tag` / `.chip` の背景はいずれも `var(--surface)`（components.css:2833, :630, :496）
  - `--bg` が実際に使われているのは、`--text` で塗った面の上の反転文字（components.css:2854 ほか）、ドロワー（layout.css:728）、`.ann-actionbar`（annotate.css:206）、color-mix の下地（SPEC-20）
- 問題: ボタンやヘッダーを `--bg` で塗る「修正」が起きかねません。そうすると ΔRGB の下限も割ります。
- 提案: CSS を正とします。design.md §1 と §3 の表で `--bg` の用途を実際の用途に書き直し、面の説明は §3 の表 1 つに集約します。tokens.css・base.css:17・CLAUDE.md:160 のコメントや記述も合わせます。
- 影響ファイル: docs/design.md, CLAUDE.md, app/assets/stylesheets/tokens.css, app/assets/stylesheets/base.css
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-04] 「管理画面はトークンだけを上書きし、コンポーネントには触らない」は事実と違う
- 観点: A ／ 確度: 確認済み
- 根拠（文書側）: CLAUDE.md:179-181「トークンだけ上書きする…個々のコンポーネントには触らない」、design.md:602-603、admin.css:13-14 も同じ趣旨
- 根拠（実物）: admin.css は次のコンポーネントを直接上書きし、色も 2 つ追加しています。
  - 上書き: `.admin-card:hover`（:108）、`.stats-grid` 一式（:126-165）、`.data-table thead th`（:225）、`.btn[data-turbo-confirm]` / `.btn--danger`（:247-258）、`main a:not(...)`（:262）、`.admin-nav__link[aria-current]`（:274-279）
  - 追加色: `--admin-accent: #1d4ed8` / `--admin-warn: #b45309`（:98-101）
  - design.md §10.1.1 と §10.1.3 自身も、コンポーネント単位の変更を説明している
  - CLAUDE.md は :114「アクセントカラーを持たない」と書く一方、管理画面の 2 色には触れていない
- 問題: 規約違反と誤解して、管理画面専用の上書きや 2 色を消す（あるいは別ファイルへ散らす）変更が起きえます。
- 提案: 規則を「公開側のコンポーネント定義は変えない。`.is-admin` 配下の上書き（トークンと管理画面専用の見た目）は admin.css に集約する」と書き直し、CLAUDE.md に管理画面の 2 色を明記します。
- 影響ファイル: CLAUDE.md, docs/design.md §10, app/assets/stylesheets/admin.css（冒頭コメント）
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-05] 濃い「章の罫」は「4 箇所だけ」とされているが、実際は 5 箇所
- 観点: A ／ 確度: 確認済み
- 根拠（文書・コメント側）:
  - CLAUDE.md:154「design.md §3 に列挙した4箇所だけ」
  - design.md:222-227（4 項目の列挙）、design.md:412「§3 の 4 箇所だけ」
  - components.css:191「サイト内で唯一、罫に文字色を使う場所」、components.css:316-318「4 箇所だけ」
- 根拠（実物）: `border-*: 1px solid var(--text-muted)` は次の 5 箇所にあります。
  - layout.css:356 `.sheet`（ホーム。design.md:297 の §5.2 の表には載っている）
  - components.css:142 `.entry-toolbar`、:193 `.page-header:not(--rail)`、:1314 `.search-actions`、:4718 `.rank-tabs`
- 問題: 「増やすな」という上限の規則が不正確なため、`.sheet` を違反とみなして消す、または件数の判定を誤る恐れがあります。
- 提案: 一覧は design.md §3 の 1 つだけにして、`.sheet` を加えた 5 箇所を列挙します。CLAUDE.md からは箇所数を消し「§3 に列挙した箇所だけ」とします。components.css:191 の「唯一」も直します。
- 影響ファイル: CLAUDE.md, docs/design.md, app/assets/stylesheets/components.css
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-06] design.md の現行仕様の節に、上書き前の古い値が残っている（同じ文書の別の節や CSS と矛盾）
- 観点: A ／ 確度: 確認済み
- 根拠（古い記述 ↔ 実物）:
  - design.md:215「一覧やリストは区切り線を引かない」 ↔ design.md:187-196・:343、components.css:971-973（`gap:1px` で罫を見せる）
  - design.md:374「語義ごとに `--bg-soft` の角丸カード（枠なし）」 ↔ design.md:183、components.css:372-376 `.sense-card{border:1px solid var(--border)}`（背景なし）
  - design.md:391「1 枠 = `--bg-soft` の角丸カード」 ↔ components.css:4747-4751 `.rank-board{border:1px solid var(--border)}`
  - design.md:396「最終行は引かない」 ↔ `.rank-list` は gap 方式（:4797）
  - design.md:127「見出し 1.7」 ↔ base.css:35 `line-height: 1.75`
  - design.md:132-135「ページ見出し 21px／ホームのヒーロー見出し 24px」 ↔ components.css:262-263 `.page-header .page-title{font-size:24px}`（公開ページの大半）、:1162-1163 `.hero__title{font-size:26px}`。21px になるのは `/search`（searches/index.html.erb:9）だけ
  - design.md:139「11px 未満にしない」 ↔ 10px の要素がある: layout.css:79 `.site-brand__roman`（design.md:273 自身も「10px」と書く）、components.css:2072 `.ring-art__caption`（design.md:443「10px」）、:4583 `.vowel-graph__tick`
  - design.md:496-497「`components.css` のコメントにもそう書いてある…直すのは Issue 84」 ↔ components.css:2115-2118 は既に「4.65 秒が正」に直っており、Issue 84 も完了済み（changelog.md:308）
  - design.md:695「撤去後 156.4ms」 ↔ admin.css:57「なし 175.1ms」
- 問題: 同じ文書のどちらの節を正とするかで、変更の向きが逆になります。
- 提案: CSS を正として（いずれも後から実測して決めた値）design.md の該当行を直し、10px の例外は §2 に列挙します。
- 影響ファイル: docs/design.md（admin.css のコメントの数値とも揃える）
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-07] 「ジャンル数」「分類数」の定義が 3 通りあり、「同じ定義に揃える」というコメントが事実と違う
- 観点: D・A ／ 確度: 確認済み（nil のキーが実際に数に混ざるかどうかは推測）
- 根拠:
  - genres/index.html.erb:20-21 のコメント「数はホームの「ジャンル数」と同じ定義に揃える」、:25 の実装は `@published_counts.size`
  - その `@published_counts` は published_sense_counts.rb:22 の `WordSense.published.group(:genre_id).count`（nil のキーも含みうる）
  - ホームは home_controller.rb:15 で `Genre.small.count`（マスタにある小分類をすべて数える。未使用の分類も含む）。表示名は ja.yml:216「ジャンル数」
  - 統計は site_statistics.rb:120 で `where.not(genre_id: nil).distinct.count(:genre_id)`（表示名「使用ジャンル」）
- 問題: 画面ごとに数が食い違ううえ、どれが正しいのかを辿れません。
- 提案:
  - 当面はコメントを事実に直します（外部への影響なし）。
  - 定義を 1 箇所にまとめる（例: `PublishedSenseCounts.genre_count`）のは、ホームの表示値が変わるので**計画書への提案のみ**とします。
- 影響ファイル: app/views/genres/index.html.erb, app/controllers/home_controller.rb, app/models/site_statistics.rb, app/models/published_sense_counts.rb
- リスク: 中 ／ 外部振る舞いへの影響: コメントの修正はなし。定義を統一する場合はあり（表示値が変わる）

### [SPEC-08] SeedCatalog のコメントが、ジャンル一覧の正の向きを逆に書いている
- 観点: A・D ／ 確度: 確認済み
- 根拠:
  - seed_catalog.rb:15「出典: docs/genres.md」 ↔ overview.md:145「名前リストは SeedCatalog が単一の正」、issues.md:48「genres.md は `SeedCatalog::GENRES` を…写したもの」、Issue 85（genres.md をコードから生成する計画）
  - seed_catalog.rb:8「RENAMES に 旧名 => 新名」 ↔ `RENAMES` という定数は無く、実際は種類ごとの `GENRE_RENAMES` / `WORD_ORIGIN_RENAMES` / `PART_OF_SPEECH_RENAMES` / `LINGUISTIC_FEATURE_RENAMES`（:196, :217, :227, :266）
- 問題: ジャンルを足したいエージェントが genres.md を編集し、seed に反映されないまま終わります。
- 提案: コメントを「docs/genres.md はこの定数を写した一覧（Issue 85 で生成に切り替える予定）」に直し、`*_RENAMES` と正しく書きます。
- 影響ファイル: app/models/seed_catalog.rb
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-09] stats.md のリンク先・紙面の順序・章題・奥付が実装と違う
- 観点: A ／ 確度: 確認済み
- 根拠:
  - リンク先: stats.md:47「`search?reading_length=` 等」、:169「`search?reading_length=n`」、:298「`search?linguistic_feature_id=`」 ↔ 実装はいずれも `words_path(...)`（_length_chart.html.erb:16、_feature_ranking.html.erb:10、_kana_heatmap.html.erb:14）。`/search` は noindex のフォームページ（searches/index.html.erb:4）
  - 順序: stats.md:56-58「上から順に。0. ページヘッダ + 数字の壁」→ §1 ワードクラウド ↔ stats/index.html.erb:18-28 ではワードクラウドが数字の壁より先
  - 章題: stats.md の §2「音のはじまりとおわり」・§6「ことばの出どころ」・§7「音の内訳」・§8「ことばの見どころ」 ↔ 画面の見出しは ja.yml:1197「頭文字と末尾文字」・:1241「語種とエンティティ型」・:1252「母音と子音」・:1272「言語学的特徴」。コードのコメント（site_statistics.rb:128, :220, :264, :352）は文書側の名前を使っている
  - 未実装の記述: stats.md:158 の読み物キャプション 3 本 ↔ _sound_matrix.html.erb:61-67 には最多の注記 1 本しかない
  - 文言: stats.md:61・:302「毎日再集計」 ↔ ja.yml:1148・:1151
- 問題: 統計ページの図に `/search` へのリンクを足すなど、noindex の URL を増やしかねません（CLAUDE.md が警戒している URL 空間の問題）。画面の文言で検索しても文書の節に行き着けません。
- 提案: 実装を正として stats.md を直し、章ごとに「画面の見出し（ja.yml のキー）」を併記します。
- 影響ファイル: docs/stats.md
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-10] issues.md の確定事項16・18 が、廃止された朱・墨の配色に注記なしで残っている
- 観点: A ／ 確度: 確認済み
- 根拠: issues.md:436「朱は「最」にだけ」、:438「墨枠タグクラウド」「朱下線つきランキング」 ↔ design.md:40-41「過去のデザイン判断(…朱一色…)はすべて失効」、stats.md:34-36「朱・墨の配色は廃止」。issues.md:13 は「後から覆った判断には、覆した先への注記を残す」と約束している
- 問題: 「確定事項」を根拠に朱を復活させる差し戻しが起きえます。
- 提案: 両項目に「→ 2026-09-03 に失効（Issue 82 のデザイン刷新）。現行は stats.md の『チャートの文法』」と注記します。
- 影響ファイル: docs/issues.md
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-11] 凍結した performance-report.md の §8「残課題」が、その後の判断と整合していない
- 観点: A・C ／ 確度: 確認済み
- 根拠:
  - performance-report.md:12-15 は「速度に手を付ける前に本書を読む」「残課題は §8」と案内している
  - §8-5（:467）「`icon` ヘルパー→定数 SVG」 ↔ issues.md:108（Issue 88）「効果が 1ms 未満だったので取り下げた」
  - §8-6（:468-469）set_navigation ↔ changelog.md:310（Issue 98 で見送り）
  - §8-2（/admin/tags/genres）と §8-7（keyset）は、どの Issue にも載っていない
- 問題: 案内に従って本書を読んだエージェントが、取り下げ済みの改修をやり直す恐れがあります。
- 提案: 本文は凍結のまま、冒頭に「§8 の現状は issues.md（Issue 53・88・97・98）を見る。§8-5 は取り下げ済み」という案内を 1 行足します。文書全体は docs/history/ へ移します。
- 影響ファイル: docs/performance-report.md
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [SPEC-12] 最新の 3 つのマージが changelog.md に記録されておらず、overview の CSS 一覧にも漏れがある
- 観点: A・C ／ 確度: 確認済み
- 根拠:
  - issues.md:34-36 は「PR だけで進めた改善は changelog.md の「番号を持たない改善」節に 1 行残す」と定めている
  - 対象のマージ: #162（6dca315、登録予定単語）、#163（35de5e2）、#164（a04f375、管理画面の共通ナビとダッシュボード）
  - changelog.md / issues.md を「登録予定」「candidate」「#16[2-4]」で検索しても 0 件
  - overview.md:39・:143 の CSS 一覧は「admin / annotate」だけで、application.css:12 が読み込む candidates.css が抜けている
- 問題: 大きな機能（登録予定単語）の由来と判断の経緯が文書から辿れません。
- 提案: changelog に 3 行追記し、overview に candidates.css を加えます。
- 影響ファイル: docs/changelog.md, docs/overview.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-13] 収録基準（読み 10 文字以上）がモデルの検証になっていない前提が、どこにも書かれていない
- 観点: E・D ／ 確度: 規則の所在は確認済み。「コンソールで 10 字未満の読みが保存できる」という帰結は推測
- 根拠:
  - 規則側: annotation-guidelines.md:16-17「読みが10文字未満の語は…収録しない」、CLAUDE.md:89「バリデーションはモデルと DB 制約の両方」
  - 実装側: word_sense.rb:33 に `MIN_READING_LENGTH = 10` はあるが、:39 の検証は `validates :reading, presence: true` だけ。基準を当てているのは bulk_word_registration.rb:42-44（確認画面で既定で除外）とリクエスト画面の字数表示だけ
  - word_requests_helper.rb:3 は「MIN_READING_LENGTH を単一の正」とするが、ja.yml:191, 291, 409, 848, 1291, 1310 と script/og_default.py:132 は「10」を直書きしている
- 問題: 基準がどの層で守られているかを誤解し、テストや修正の場所を間違えます。
- 提案: data-model.md か annotation-guidelines.md に「基準は登録時の UI で当てる。モデルでは検証しない」と明記します。モデルに検証を足すのは、既存データや保存の挙動に関わるので**計画書への提案のみ**とします。
- 影響ファイル: docs/annotation-guidelines.md（または docs/data-model.md）、app/models/word_sense.rb
- リスク: 中 ／ 外部振る舞いへの影響: 明記するだけならなし。検証を足す場合はあり

### [SPEC-14] 文書とコメントの参照が壊れている
- 観点: A・C ／ 確度: 確認済み（issues.md:336 の件だけ推測）
- 根拠:
  - issues.md:492 が挙げる「docs/improvements.md」は、どのブランチにもコミットされたことがない（`git log --all` で 0 件）。そのため Issue 86〜105 が出典として挙げる「改善調査 A-5 / A-2 / B-1 / A-7 / C-1 / C-3 / D-2」（issues.md:101, 120, 135, 295, 310, 323, 336）を辿れない
  - issues.md:135「`word_sense.rb:251-258`」 ↔ `KEYWORD_MATCH_CONDITION` の定義は word_sense.rb:46
  - issues.md:126「importmap の pin を削除」 ↔ config/importmap.rb に plotly の pin は無い。Sprockets 経由で配信している（app/assets/config/manifest.js:4、genre_sunburst_controller.js:62「importmap には載せず」）
  - CLAUDE.md:221「issues.md Issue 80・81」 ↔ 両 Issue の本文は changelog.md:147 と :158 にあり、issues.md には無い
  - issues.md:336「(確定事項・Issue 74)」は確定事項の番号が書かれていない（推測: 該当する番号が見当たらない）
- 提案: 行番号で参照せず、シンボル名（定数名・メソッド名）で参照します。improvements.md は「未コミットのため参照不可」と注記するか、要点を issues.md に取り込みます。CLAUDE.md の参照先は changelog.md に直します。
- 影響ファイル: docs/issues.md, CLAUDE.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-15] 現状と矛盾する古いコードコメント（まとめて列挙）
- 観点: A ／ 確度: 確認済み
- 該当箇所:
  - home/index.html.erb:21「左に見出しと検索、右のレールに収録語数」 ↔ 直後の :22-23 が現行の説明（古い行が重複して残っている）
  - home_controller.rb:32「新着より上に置く」 ↔ ビューでは新着の後（home/index.html.erb:156-212）。あわせて :6 `RANKING_LIMIT = 10` なのに、ビューは `.take(5)`（:198）で 5 件しか出さない（B: 5 が直書き）
  - stats_helper.rb:356「2周期」 ↔ `WAVE_CYCLES = 1`（:22）、stats.md:165「1周期」。同じ行の「見立て」は stats.md:7 が使わないと決めた言い回し
  - site_statistics.rb:256「エンティティ型のタグクラウド用」 ↔ 実装は squarified ツリーマップ
  - stats/_sound_matrix.html.erb:2「10×11」 ↔ 同じファイルの :11「11×11 の正方形」
  - components.css:1900-1901（`.label-en`）「白抜きが成立する最小」 ↔ 標識は塗り。白抜きは不採用（design.md:445-458）
  - components.css:1963-1964「額装…細い枠でひと区画を囲い、縦罫で本文と数字に分ける」 ↔ design.md:321「面も枠も持たず」の 1 列中央揃え
  - components.css:2164（`.home-column`）「2カラムと帯を」 ↔ 縦に積む（design.md:337）
  - components.css:284-290（`.word-flavor`）「細罫の下に」 ↔ 実装は `--bg-soft` の角丸の面
  - components.css:306-309（`.prose`）「幅は他の要素と同じだけ取る」 ↔ `max-width: var(--reading-width)`（640px）
  - components.css:3707-3708・:4586、stats/_sound_breakdown.html.erb:3 が「アクセント（色）」と書く ↔ トークンは `--chart`。design.md は「アクセントカラーを持たない」
  - tokens.css:19-20「構造は罫ではなく「余白」で作る」 ↔ CLAUDE.md:157「色ではなく罫で解く」、layout.css:346-349
  - words/_entry_row.html.erb:3「見出しと読みは同じ行に組んで」、:25「文字数は…右端の独立した列」 ↔ components.css:997-999・:1009-1011（見出し語と読みは左列に縦積み、文字数は右列の 2 段目）
  - words/show.html.erb:88「docs/design.md §5.2」 ↔ グループルビの説明は §5.4（design.md:375-377）
- 提案: いずれもコメントを現状に合わせて直します。
- 影響ファイル: 上記の各ファイル
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-16] 「最頻の語を --chart で印す」表示は廃止されたのに、文書の記述とフラグが残っている
- 観点: A・C ／ 確度: 確認済み
- 根拠:
  - stats.md:93「最頻のみ `--chart`」 ↔ 同じ文書の :141「…印はやめた」、design.md:526
  - morpheme_cloud.rb:108-109・:428 の `Placed#top` と、morpheme_frequencies.rb:20 の `Entry#top?` は、どのビューも読んでいない。中心に据える処理は :220 の `index.zero?` で決まる
  - 使っているのはテストだけ（morpheme_cloud_test.rb:56、morpheme_frequencies_test.rb:34-35・:89）。:89 の失敗メッセージは「朱にする最頻は1件だけ」
- 提案:
  - stats.md:93 を消します。
  - `Placed#top` は用途を「中心に据える最頻語」と注記するか削除します。
  - テストの失敗メッセージを直すのは**計画書への提案のみ**とします（期待値そのものは変えない）。
- 影響ファイル: docs/stats.md, app/models/morpheme_cloud.rb, test/models/morpheme_frequencies_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-17] stats.md の「§N」が 2 系統あり、参照先がどちらか分からない
- 観点: A ／ 確度: 確認済み
- 根拠:
  - 文書の節（stats.md:29「## 1. デザインコンセプト」〜 :337「## 5. 掲載統計カタログ」）と、紙面の章（:78「### §1 看板」〜 §8）が、同じ番号を使っている
  - stats_helper.rb:25「全点に数字を振らない。docs/stats.md §1」は文書の「## 1」を指す
  - design.md:528「stats.md §1」は紙面の章（ワードクラウド）を指す
  - changelog.md:278「stats.md §5.2」は文書の「## 5.2」を指す
  - components.css の §3・§4・§7・§8（:4006 ほか）は文書名を書かず、design.md と stats.md のどちらの節かも混在している
- 提案: 文書の節を「## A.〜」のように別の記号へ改め、コメントでは必ず文書名を付けて参照します。
- 影響ファイル: docs/stats.md, app/helpers/stats_helper.rb, app/assets/stylesheets/components.css
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-18] 立項スコアと確信度（confidence）のしきい値が各所に直書きされている
- 観点: B・D ／ 確度: 確認済み
- 根拠:
  - スケールの定義は annotation-guidelines.md:123-134
  - annotation_proposal.rb:18（SQL）と :114（Ruby）に `<= 3` が別々に書かれている。:19 は `'low'` を直書き
  - bulk_proposal_approval.rb:15-16 は `"high"` と `>= 4` を直書き
  - word_candidate.rb:23・:26 は `CONFIDENCES` と `DOUBTFUL_ENTRY_SCORE = 2` を定数で持つ。根拠としてスキルの文書（.claude/skills/word-notation-research/SKILL.md:74-78。スコア表そのものも重複して載っている）を挙げている
- 提案: 基準値の持ち主にあたる定数（例: `AnnotationProposal::OWNER_REVIEW_MAX_SCORE` と、共有の `CONFIDENCES`）へ集約し、コメントで guidelines §2 を参照します。正典のパターンは WordCandidate のように定数で持つ形とします。
- 影響ファイル: app/models/annotation_proposal.rb, app/models/bulk_proposal_approval.rb, app/models/word_candidate.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-19] 「言語的特徴だけの再調査」の書き出しに、受け取る側が存在しない
- 観点: C ／ 確度: 受け取るスキルが無いことは確認済み。実際に使われていないかは推測
- 根拠:
  - 実装: feature_research_export.rb:1-9、config/routes.rb:92、admin/words/index.html.erb:71、ja.yml:916「Claude Code に貼り付けてください」
  - 判断: issues.md:483「専用の調査スキルは作らない」、:494「遡及付与は行わない」。.claude/skills/ に特徴を調べるスキルは無い
- 提案: 画面の説明文を「/reannotation で 1 語ずつ」に改めるか、書き出しの口ごと撤去します（オーナー判断なので**計画書への提案のみ**）。「特徴なしで確定」（features_reviewed_at）は新規の注釈でも使うので残します。
- 影響ファイル: 上記の各ファイル
- リスク: 中 ／ 外部振る舞いへの影響: なし（管理画面だけ）

### [SPEC-20] 同じ目的の書き方が 2 通りずつある（正規化の式、color-mix の下地）
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 最小値〜最大値を 20〜100% に写す正規化が 2 箇所にある: radial_chart.rb:13-15・:33（`MIN_RATIO`）と、genres/index.html.erb:37 のラムダ（20 と 80 を直書き）。規則は design.md:514
  - design.md:111 と stats.md:43 は色の濃淡の書き方を「`color-mix(..., transparent)`」とだけ定めている ↔ components.css:4212-4226（ワッフル）、:4294（ツリーマップ）、:4393-4405（スペクトル）は `var(--bg)` を下地に混ぜている。:684・:706・:3984 は `transparent`
- 提案:
  - 正規化は `RadialChart` の式を正とし、ビューからもそれを呼びます。
  - color-mix は「不透明な塗りが要る場合は `--bg`」という使い分けを文書に書きます。見た目を統一する変更は**計画書への提案のみ**とします。
- 影響ファイル: app/views/genres/index.html.erb, app/models/radial_chart.rb, docs/design.md
- リスク: 低 ／ 外部振る舞いへの影響: なし（見た目を統一する場合はあり）

### [SPEC-21] 「fragment cache」という呼び名が、実際には集計結果の Rails.cache を指している
- 観点: A ／ 確度: 確認済み
- 根拠: growth-strategy.md:95「fragment cache は `PublishedSenseCounts` に集約済み」、changelog.md:56（Issue 48 の見出し） ↔ issues.md:323（Issue 97）「ビュー内の `cache` ブロックは1箇所だけ…描画結果はどのページでもキャッシュしていない」、published_sense_counts.rb:22-29
- 提案: 呼び名を「集計キャッシュ」に改めます。
- 影響ファイル: docs/growth-strategy.md, docs/changelog.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-22] デザイン改訂の「何回目」の番号が、design.md と changelog.md で食い違っている
- 観点: A ／ 確度: 確認済み
- 根拠: design.md:14「④の画像帯は 5 回目に撤去」、:15-20（4 回目＝ニューモーフィズム、5 回目＝ホームを 1 枚の紙に） ↔ changelog.md:173「7回目で撤去」、:186（5 回目＝ニューモーフィズム）、:195（7 回目＝ホームを 1 枚の紙に）
- 提案: 改訂履歴は docs/history/ の 1 か所にまとめ、番号を付け直すか日付だけで呼ぶようにします。
- 影響ファイル: docs/design.md, docs/changelog.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-23] growth-strategy.md §0 の「About・llms.txt・共有カードの文言は home.index.* から派生」が事実と違う
- 観点: A ／ 確度: 確認済み
- 根拠: growth-strategy.md:21 ↔ llms/full.text.erb:3・:15-16 は `pages.about.*` を使う。script/og_default.py:131 の LEAD（「…読み・文字・韻・ジャンルから眺める」）は ja.yml:190 のタグラインとも違う文面を直書きしている
- 提案: 文言の出どころを正しく書き直します。
- 影響ファイル: docs/growth-strategy.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [SPEC-24] 役目を終えた「不在確認」のテストが残っている
- 観点: C ／ 確度: 確認済み
- 根拠: test/controllers/pages_controller_test.rb:31 `assert_select ".image-slot", count: 0` ↔ CLAUDE.md:207「もう無いマークアップの「不在」確認…は残さない」
- 提案: 削除します（テストの変更なので**計画書への提案のみ**）。
- 影響ファイル: test/controllers/pages_controller_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし

---

## 1. docs/ の各文書（担当分）の分類案

- **design.md: 混在**
  - 現行仕様: §0〜§10 の規則と値（SPEC-02〜06 を直したうえで）。
  - 歴史へ移すもの: 冒頭の改訂履歴（:6-41）、§3 の「ただ、そこ」の採寸（:179-182）、§5.2 の罫を伸ばす試作（:312-314）、§5.6.1 のページ内もくじ（:415-416）、§5.7 の About の 5 案の表（:427-438）、§5.8 の白抜きの実測（:445-458）、§5.9 の印を差し替える案（:487-490）、§10.2 の計測（:687-698）。
  - 「再提案しない」の扱い: 規則として 1 行だけ本文に残します（ニューモーフィズム不可、`.image-slot` を再導入しない、About に図を置かない、標識は塗り、印の読みはサイト名から変えない、全称セレクタで transition を潰さない）。実測値と経緯は歴史側へリンクします。これらは現行の規約として必要です。
- **stats.md: 混在**
  - 現行仕様: 「チャートの文法」と §0〜§8 の紙面。
  - 歴史へ移すもの: 冒頭の「実装後のオーナー修正」（:6-18）、デザインモックへのリンク（:22-24）、§1 の組み直しの経緯（:107-145 の叙述部分。値と規則は残す）、「3. 実装フェーズ」（:306-318）。
  - 「4. 追加アイデア」「5. 掲載統計カタログ」（:322-382）は構想なので、issues.md へ移すか歴史へ移します。
- **annotation-guidelines.md: 現行仕様**。「運用」節に登録予定単語（`/admin/candidates`）の流れを足すかは未確認です。
- **performance-report.md: 歴史・記録**（既に凍結済み）。docs/history/ へ移し、冒頭に「現行の仕様ではない。§8 の現状は issues.md」と書きます。§9 は overview.md §7 と重複しているので、正は overview にします。
- **issues.md: 混在**
  - 現行: 未完了イシュー。
  - 確定事項は「有効な決定」と「失効・上書き済み」に分けます。有効な例: 3, 4, 19, 20, 28, 31, 32, 33, 37。失効・上書き済みの例: 5, 10〜18, 25（16 と 18 は注記を追加）。
- **changelog.md: 歴史・記録**。docs/history/ へ移し、冒頭の「本ファイルは当時の記録」はそのまま残します。
- **growth-strategy.md: 混在**
  - 現行: §0 と §3 の KPI ツリー。
  - 歴史へ移すか書き直すもの: 評価記号（◎△✗）つきの現状評価と「現フェーズの優先順位」。

## 2. 同じ事実が複数の文書に書かれている箇所と、単一の出典案

| 事実 | 書かれている箇所 | 単一の出典案 |
|---|---|---|
| 章の罫の一覧 | CLAUDE.md:153-154、design.md §3・§5.2・:412、components.css:191・:316-318、changelog.md:181 | design.md §3 |
| 面の段と `--bg` の役割 | CLAUDE.md:158-162、design.md §1・§3、tokens.css、base.css:17、layout.css:6-7 | design.md §3 |
| 管理画面で上書きするトークン | CLAUDE.md:178-183、design.md §10.1、admin.css の冒頭 | design.md §10 |
| 印の描画速度 | design.md:491-497、issues.md:478、changelog.md:210・:214、components.css:2098-2118 | CSS の値と design.md §5.9 |
| ワードクラウドの色 | design.md:101-110・§5.10、stats.md:138-142、tokens.css:33-36 | design.md §5.10 |
| ワードクラウドの組み方 | stats.md §1、changelog.md:143、morpheme_cloud.rb | stats.md §1 と定数 |
| 収録基準（10 字） | CLAUDE.md:10、overview.md:24、guidelines §0、issues.md 確定事項3、ja.yml（6 箇所）、og_default.py | 方針は guidelines §0、値は `WordSense::MIN_READING_LENGTH` |
| 立項スコアの表 | guidelines §2、word-notation-research の SKILL.md:74-78 | guidelines §2 |
| 収録日＝annotated_at | stats.md:71-73、overview.md:69-70、home_controller.rb:16-19、site_statistics.rb:113-114 | overview §4（推測: data-model.md のほうが適切かもしれない） |
| Plotly の例外 | overview.md:44-45、stats.md:12-15・:49・:196、Issue 90 | stats.md §5 |
| 開発環境はキャッシュ無効 | overview.md:169-170、performance-report §9 | overview.md |
| MeCab の辞書の使い分け | overview.md:180-181、stats.md:101-103、changelog.md:142 | overview.md §7 |
| 共有カードの組み | design.md:261-272、changelog.md:50 | design.md §5.1 |
| 改訂の回数 | design.md の改訂履歴、changelog.md の Issue 82 | history の 1 文書 |
| 特徴の遡及付与・Bing | issues.md 確定事項25・32・33・37、changelog.md:298-301、growth-strategy | issues.md の確定事項 |

## 3. コメントの傾向

- 文書・Issue・日付を参照するコードコメントは約 445 行あります（app 332、test 85、config 26、lib 1、script 1）。
- 種類別の内訳: Issue 番号 274、§ 番号 98、`docs/` のパス 79、日付 59、確定事項 6、PR 番号 2。
- 参照先の実在: 参照されている Issue 番号（8〜100）と `docs/` のパスは、すべて実在しました。PR #114 と #116 も changelog に載っています。
- 壊れた参照・誤った参照:
  - words/show.html.erb:88 の「design.md §5.2」（正しくは §5.4）
  - stats_helper.rb:25 の「stats.md §1」（どちらの §1 か曖昧）
  - seed_catalog.rb:15 の「出典: docs/genres.md」（正の向きが逆）
  - seed_catalog.rb:8 の「RENAMES」（その名の定数は無い）
  - design.md:496-497（既に直ったコメントを「こう書いてある」と説明している）
  - CLAUDE.md:221 の「issues.md Issue 80・81」（本文は changelog.md にある）
  - issues.md:135 の「word_sense.rb:251-258」（実際は :46）
  - issues.md:492 の「docs/improvements.md」（一度もコミットされていない）
  - components.css の文書名なしの「§N」（:316, :515, :1900-1901, :4006, :4056, :4333, :4380, :4420, :4641, :4795）
  - morpheme_frequencies_test.rb:89 の「朱にする最頻」（廃止された概念）

## 未確認のまま残した範囲

- **design.md**: §5.1 のフッターの細部、§5.6 の入力部品の大きさ、§6 のタップ領域、§7、§9.2〜9.3（インラインスクリプト・theme-color・ARIA）、§10.1.2〜10.1.3 の実測値、WordShareCard の組みの詳細。
- **stats.md**: §4 の線の太さと面の濃さ、§5 の Plotly のオプション（branchvalues、rotation、colorway）、§6 のワッフルの凡例（5 値）、§7 の操作規則（vowel_graph_controller.js）と `vowel_transition` の値の範囲（2〜15 拍、位置 1〜30）、§8。
- **annotation-guidelines.md**: word-notation-research 以外の SKILL.md との整合、research/README.md、登録予定単語の流れの記述の要否。
- **performance-report.md**: 数値の主張（再計測はしていない）、インデックス 16 本、WordSenseMetrics が updated_at を動かさないこと。
- **issues.md**: 各 Issue の「現状」の記述（Issue 77 の 6 種、Issue 83、Issue 27 の config.hosts、Issue 95 の 7 本のルート。`bin/rails routes` は実行していない）、確定事項19・20・31 とコードの突き合わせ。
- **changelog.md**: Issue 1〜81 の記載と実装の突き合わせ。
- **コードコメント**: Issue を参照する約 274 行の内容の個別照合（照合したのは番号の実在だけ）。
- 所有者の未コミットの作業中の変更。

### Critical Files for Implementation
- docs/design.md
- CLAUDE.md
- docs/stats.md
- docs/issues.md
- app/assets/stylesheets/components.css

## 棚卸し（a668f8c）

- 前提: `git diff a04f375..a668f8c` で、この監査の対象（docs の仕様・記録系の文書と、それを参照するコードコメント）は 1 行も変わっていない。行番号はそのまま使える。
- **陳腐化: 0 件。**
- **重複**（計画書 §9 で同じ改修項目に束ねてある）:
  - SPEC-03・SPEC-04・SPEC-05 ↔ S-01・S-07・S-13（design.md と CSS の食い違い。D1-09・D1-16）
  - SPEC-07 ↔ C-08（ジャンル数の定義）
  - SPEC-18 ↔ M-10（しきい値の散在。C3-01）
  - SPEC-19 ↔ DOC-11（言語的特徴だけの再調査の書き出し）
  - SPEC-24 ↔ T-13（不在確認のテスト。§7.3）
- **要確認**:
  - SPEC-07: nil のキーが実際に数に混ざるかは推測。§7.5（オーナー判断）に回してあるので、判断の材料として P-01 で 1 回だけ確かめる。
  - SPEC-14: issues.md:336 の件だけ推測。D1 で直すときに確かめる。
  - SPEC-19: 実際に使われていないかは推測。オーナーに使っているかを聞けば決まる（P-04 の質問に入れる）。
- **この棚卸しで決着したもの**:
  - SPEC-13 の「コンソールで 10 字未満の読みが保存できる」: `app/models/word_sense.rb:39` の検証は `validates :reading, presence: true` だけ。`MIN_READING_LENGTH` を使っているのは、一括登録（`bulk_word_registration.rb:44`）、収録リクエストのヘルパ、重複確認画面だけ。**コードの上では保存できる**（実行はしていない）。修正は §7.1 のまま。
- **台帳 §3.2 に回したもの**（B-03・B-05・B-07 から預かった分を含む）:
  - A-05 に、stats.md §4〜§8（線の太さ・Plotly のオプション・ワッフルの凡例・母音遷移の操作規則と値の範囲）と実装の照合を足した。統計のパーシャルを読む単位と同じ実物を見るため。
  - A-10: design.md の未照合の節（§5.1 フッターの細部・§5.6 入力部品・§6 タップ領域・§7・§9.2〜9.3・§10.1.2〜10.1.3）と CSS・レイアウトの照合。CLAUDE.md が UI を触るときに必ず読む文書なので、嘘があると影響が大きい。
  - A-11: annotation-guidelines.md と、注釈・再注釈・読み・拡張・収穫の各 SKILL.md、および SeedCatalog のマスタの突き合わせ（B-05 から）。
- **見送るもの**（文書を 1 行ずつ照合するのではなく、計画書 §4.7 の扱いで解く）:
  - issues.md の各 Issue の「現状」、changelog.md の Issue 1〜81、performance-report.md の数値: いずれも**記録**であって、現行の仕様ではない。照合して直す代わりに、P-01 で「記録の文書は冒頭で記録であることを明記し、現行の仕様の根拠にしない」を正典に入れるかを決める。B-03 から預かった「issues.md・changelog.md の JS 関連の確定事項との照合」も同じ扱いにする。
  - Issue を参照する約 274 行のコードコメント: 計画書 §4.7「経緯は docs/history か changelog へ移す」で、実行の段階に書き換える。1 行ずつの事前照合はしない。
