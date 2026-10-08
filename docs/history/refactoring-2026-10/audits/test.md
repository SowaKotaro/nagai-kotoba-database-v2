> フェーズ1の監査報告（担当: test）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# test/ 領域 監査報告（ID: T-）

前提:
- 根拠欄のパスはリポジトリルート `` からの相対パスです。影響ファイル欄と末尾の一覧は絶対パスで書いています。
- テスト・DB・rake は一度も実行していません（`bin/rails routes` も使っていません）。
- 未コミットの作業中の変更（README.md、.claude/ 配下）には触れていません。
- 既に報告済みとされた2件（pages_controller_test.rb:31 の `.image-slot`、application_system_test_case.rb の Google Fonts 遮断と「sticky ヘッダー」のコメント）は重ねて書いていません。

参考（テスト数。`^\s*test "` を grep。`def test_` は0件）:
- 合計 809。
- 内訳: models 500、controllers の公開側 74・admin 108・admin/candidates 13・words 2、integration 40、system 26、helpers 24、services 17、tasks 3、assets 2。
- test/assets/design_tokens_test.rb:10-21 はループでテストを生成するため、実行時は約 811 になります。

assert の無いテスト、`assert_nothing_raised` だけのテスト: **該当なし**（確認済み）。
- `grep -rn assert_nothing_raised test` は0件でした。
- awk で各 `test "` ブロックを走査し、assert / refute / flunk / skip / click_accepting_confirm / click_expecting / click_via_js のどれも含まないブロックを探しましたが、0件でした。

---

### [T-01] 公開 JSON API のレスポンス形式がほとんど固定されていない
- 観点: E ／ 確度: 確認済み
- 根拠:
  - test/integration/words_api_test.rb:13-28 が見ているのは次の範囲だけです。
    - 語: `body["id"|"surface"|"url"|"senses"|"license"]`
    - 語義: `reading` / `meaning` / `reading_length`、`genre` は `name` だけ、`part_of_speech` / `word_origins`、`linguistic_features.first["name"]`
    - ライセンス: `license["name"]` と、`credit` がホストを含むこと
  - 一覧（:40-45）は `page` / `total_count` / `words[].surface` / `license.name` だけです。
  - 固定されていないキー:
    - app/views/words/show.json.jbuilder:7 `json.char_type_pattern`
    - 同 :13-17 の `mora_count` / `first_char` / `last_char` / `rhythm_pattern` / `vowel_pattern`
    - 同 :20-26 の `genre[].id` / `level` と、ジャンルが無いときの :26 `json.genre nil`
    - 同 :30 `entity_type`、:35-36 `target` / `target_reading`、:39-42 `variants`
    - app/views/words/_license.json.jbuilder:4 の `url`
    - app/views/words/index.json.jbuilder:5 `total_pages`、:9-12 の `id` / `url` / `readings`
- 問題: jbuilder を整理するリファクタでキーの欠落・改名・入れ子の変化が起きても、テストは通ってしまいます。外部との約束であるキーがどれなのかも、テストから読み取れません。
- 提案: words_api_test.rb にテストを足し、キーの集合と値をまとめて固定します。
  - 詳細: `assert_equal %w[id surface url char_type_pattern senses license], body.keys`
  - 語義: `%w[reading meaning reading_length mora_count first_char last_char rhythm_pattern vowel_pattern genre part_of_speech entity_type word_origins linguistic_features variants]`
  - ジャンルの要素: `%w[id name level]`
  - ライセンス: `license` をハッシュごと `assert_equal`
  - curry で `genre` が `nil` になり、`variants` が `[{"surface"=>"カリー","reading"=>"カリー"}]` になること
  - 一覧で `total_pages` があり、`words[0].keys == %w[id surface url readings]` であること
- 影響ファイル: test/integration/words_api_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし（テストの追加だけ）
- 先に必要な特性テスト: この提案自体が特性テストです。JSON 周りのどのリファクタよりも先に入れます。

### [T-02] 管理画面の「未ログインなら弾く」テストが、方針に反して再び増えている（方針が CLAUDE.md に書かれていない）
- 観点: A・B・C ／ 確度: 確認済み
- 根拠:
  - 方針はテストのコメントと changelog にしかありません。
    - test/integration/admin_authentication_test.rb:3-5「各コントローラのテストには未ログインの検証を書かない。Issue 96」
    - docs/changelog.md:316
    - CLAUDE.md のテスト節（:202-212）には書かれていません。
  - 方針を決めた後に同種のテストが再び足されています（git blame では 2ee5db04・2026-09-25。Issue 96 の e5764d2 は 2026-09-23）。
    - test/controllers/admin/word_candidates_controller_test.rb:5 `test "未ログインでは表示も手直しも弾く"`
    - test/controllers/admin/candidates/triages_controller_test.rb:5 `test "未ログインでは一覧も追加も確定も弾く"`
  - Issue 96 の整理から漏れたテスト: test/controllers/admin/inline_master_creation_test.rb:14 `test "未認証だと作成できない"`
  - 中身の無い見出しが残っています。どれも直後に別の見出しが続きます。
    - 見出し `# --- 認可: 未認証は弾く ---`
    - 場所: admin/words_controller_test.rb:16、admin/annotations_controller_test.rb:13、admin/annotation_decks_controller_test.rb:13、admin/tags_controller_test.rb:6、admin/annotation_proposals_controller_test.rb:5
  - admin/word_requests_controller_test.rb:3 のファイル説明は「認可と、一括操作」ですが、認可のテストはありません。
- 問題:
  - 見出しとファイル説明が「ここに認可のテストがある」と誤った情報を伝えています。
  - 管理コントローラを足すエージェントは近くの例を真似るので、未ログインの検証を書き足し続けます。上の3本が実際にその例になっています。
- 提案:
  1. 3本を削除します。同じことは test/integration/admin_authentication_test.rb:10-20 が全ルートについて検証しています。
     - :26 の `route.defaults[:controller].to_s.start_with?("admin/")` で、config/routes.rb:76・:88・:137-139 のルートも対象に入ります。
     - 検証内容は、ログイン画面へのリダイレクトと、全テーブルの件数・最終更新が変わらないことです。
  2. 空の見出し5箇所を削除し、word_requests のファイル説明から「認可と、」を削ります。
  3. CLAUDE.md のテスト節に1行足します。「管理アクションの未ログイン拒否は admin_authentication_test が全ルートを検証する。各コントローラのテストには書かず、setup でログインする」。
- 影響ファイル: 上の3テスト、空見出しのある5ファイル、CLAUDE.md
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 既存の test/integration/admin_authentication_test.rb:10-20 で固定されています。

### [T-03] og:image と MeCab のフォールバックで、テストされていない分岐がある
- 観点: E ／ 確度: 確認済み
- 根拠:
  - app/controllers/words/share_cards_controller.rb:13 は `return redirect_to(DEFAULT_CARD_PATH) unless png` です。
    - テストされているのは `available?` が false の場合だけです（test/controllers/words/share_cards_controller_test.rb:29-37）。
    - 次の2つは controller の層でテストがありません。
      - コマンドはあるのに `fetch` が nil を返す場合（失敗・時間切れ・RENDER_LOCK が使用中。サービス単体では share_card_renderer_test.rb:29-51 が nil を確認済み）
      - :28 の `card.drawable?` が false の場合
  - app/services/reading_extractor.rb:34 `return Array.new(surfaces.size) unless mecab_available?` は未検証です。mecab の無い CI で走るのは reading_extractor_test.rb:9-11 の空配列のテストだけです。
  - test/services/morpheme_extractor_test.rb:8 は setup でクラス全体を skip します。
    - そのため、mecab が要らない :25-28 まで走りません。
    - app/services/morpheme_extractor.rb:39 のフォールバックも未検証です。
- 問題: 「外部コマンドが無くても止まらない」は CLAUDE.md:191-192 の必須要件です。それなのに、最も起こりやすい失敗（カードを焼けなかった、mecab が無い）が固定されていません。
- 提案:
  - share_cards_controller_test.rb に次の2つを足します。
    - `available?` は true で `renderer.fetch` が nil のとき、`/og-default.png` へリダイレクトすること
    - 語義の無い公開語でも同じくリダイレクトすること
  - reading_extractor_test.rb に、`stub_method(extractor, :mecab_available?, -> { false })` で `[nil]` が返ることを確かめるテストを足します。
  - morpheme_extractor_test.rb は skip を個々のテストへ移し、`available?` を false にスタブして `[[]]` が返ることを確かめるテストを足します。
- 影響ファイル: test/controllers/words/share_cards_controller_test.rb、test/services/reading_extractor_test.rb、test/services/morpheme_extractor_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: この提案自体が特性テストです。

### [T-04] 収録リクエストの特性テストが足りず、上限値がテストに直書きされている
- 観点: E・D ／ 確度: 確認済み
- 根拠:
  - 受付停止中に「導線ごと隠す」動作が未検証です。
    - `requests_open?`（app/helpers/application_helper.rb:55）による出し分けは、app/views/shared/_header.html.erb:65、app/views/words/index.html.erb:129、app/views/layouts/application.html.erb:150、app/views/pages/about.html.erb:74 にあります。
    - 結合テストでこれを assert しているものはありません（`requests_open|request_link|new_request_path` で検索）。
    - 停止中のテスト（test/controllers/word_requests_controller_test.rb:151-160）が見ているのは、リダイレクトとレコードが作られないことだけです。
  - 重複チェックの上限が2箇所にあります。テスト :142 の `limit = 10` と、app/controllers/word_requests_controller.rb:27 の `rate_limit to: 10, within: 1.minute, only: :duplicates` です。
  - トークンの期限切れ（app/models/word_request_form_token.rb:12 `EXPIRES_IN = 1.day` で :invalid になる経路）は未検証です。:96-102 は改ざんされたトークンしか見ていません。
  - フォームの項目名が固定されていません。:28-34 が見ているのは `form[action=?]` と `input[value=?]` だけです。次の名前は固定されていません。
    - `word_request[items_attributes][0][surface]` / `[reading]`
    - `form_token`（app/views/word_requests/new.html.erb:25）
    - `origin_path`（同 :27）
    - ハニーポットの `website`（同 :30-32、controller :16）
  - 上限の取り出し方も2通りあります。controller のテスト :105 は `RATE_LIMITS.min_by(&:last).last`、モデルのテスト test/models/word_request_test.rb:47 は `RATE_LIMITS.first.last` です。
- 問題: 公開面で唯一の書き込み経路なのに、導線の出し分けや項目名が変わっても検出できません。上限を変えるエージェントは、テストの 10 を別途探す必要があります。
- 提案:
  - word_requests_controller_test.rb に次を足します。
    - (a) `with_requests_disabled` の中で、`/`・`/words?q=（該当なし）`・`/about` に `a[href^="/requests/new"]` が0件であること。受付中は出ていること。
    - (b) 期限切れのトークン（`travel_to(2.days.ago) { WordRequestFormToken.issue }`）で 422 と `expired` になること。
    - (c) new の項目名を assert_select で固定すること。
  - 上限値はアプリ側の定数（例 `DUPLICATE_CHECK_LIMIT = 10`）にしてテストから参照します。これは計画書への提案に留めます（期待値の出どころが変わるため）。
- 影響ファイル: test/controllers/word_requests_controller_test.rb、app/controllers/word_requests_controller.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: (a)(b)(c) を先に入れます。

### [T-05] 公開ページと管理者認証で、固定されていない主要な振る舞い
- 観点: E・A ／ 確度: 確認済み
- 根拠:
  - 今日の一語: app/controllers/home_controller.rb:47-57 の `offset(Date.current.jd % @word_count)` を検証するテストがありません（test/ を `today|daily|今日の` で検索して0件）。
  - ホームの検索フォーム: app/views/home/index.html.erb:29-33（`form_with url: words_path, method: :get` と `q`）が未固定です。`q` は CLAUDE.md:217 の「変えない」公開クエリ名にあたります。
  - sitemap:
    - test/controllers/sitemaps_controller_test.rb:13 の一覧 `%w[/ /words /genres /browse /stats /about /privacy]` に `/rankings` がありません。出力側の app/views/sitemaps/show.xml.builder:5 は `rankings_path` を含みます。
    - テスト名は「静的ページと公開語だけを」ですが、「だけ」は :19 で未注釈の1語が無いことしか見ていません。
  - Atom フィード: 次の3点が未検証です（test/integration/words_feed_test.rb:5-20）。
    - 件数上限 `FEED_LIMIT = 20`（app/controllers/words_controller.rb:6）
    - 絞り込みを無視すること（同 :10 のコメント、:26-27）
    - エントリの URL が canonical ホストであること（app/views/words/index.atom.builder:9）
  - ログイン後の戻り先:
    - app/controllers/concerns/authentication.rb:44 で `session[:return_to_after_authenticating] = request.url` を保存し、:49 で `|| root_url` に戻します。
    - test/controllers/sessions_controller_test.rb:13 はトップへ戻る場合だけを見ています。弾かれた URL へ戻る動作は未検証です（test/ で `return_to` は0件）。
- 提案:
  - home_controller_test.rb に、`travel_to` で日付を固定して今日の一語が決まった語になること（翌日は別の語）と、`form.hero-search[action="/words"][method=get] input[name=q]` を確かめるテストを足します。
  - sitemaps_controller_test.rb に、`<loc>` の集合をまるごと `assert_equal` する新しいテストを足します（静的8件＋公開語2件）。既存のテストは残します。
  - words_feed_test.rb に次の3点を足します。
    - 21語あっても20件になること
    - `?first_char=` を付けても内容が同じこと
    - `entry > link[href]` が canonical ホストであること
  - sessions_controller_test.rb に、「未ログインで admin_words_path を開く → ログイン → admin_words_path に戻る」を足します。
- 影響ファイル: test/controllers/home_controller_test.rb、test/controllers/sitemaps_controller_test.rb、test/integration/words_feed_test.rb、test/controllers/sessions_controller_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 上の提案がそのまま特性テストです。

### [T-06] backfill タスクが円環交差数を扱わず、テストのコメントは「ずれは検出される」と誤って書いている
- 観点: A・D ／ 確度: 確認済み（lib/tasks の担当と重なる可能性があります）
- 根拠:
  - 保存時に作る派生値は5つです。app/models/word_sense.rb の assign_reading_derivations（:148 付近）が rhythm / vowel / mora / `self.ring_crossing_count = KanaRing.crossing_count(reading)` / last_char を作ります。CLAUDE.md:33-34 も ring_crossing_count を Ruby 側の派生値に数えています。
  - backfill タスクは ring_crossing_count を扱いません（backfill.rake を `ring_crossing` で grep して0件）。
    - lib/tasks/backfill.rake:7 の説明は「(rhythm_pattern/vowel_pattern/mora_count/last_char)」です。
    - :12-17 の再生成にも、:46-51 の検証にも入っていません。
  - つまり算出式がモデル・reading_metrics・verify の3箇所に重複していて、すでに食い違っています。
  - test/tasks/backfill_task_test.rb:41 のコメント `# フィクスチャの派生値は読み・表層形と整合させてある(ずれていればここで検出される)` は、ring_crossing_count については成り立ちません。
    - 現在の値が正しいことは手計算で確かめました（test/fixtures/word_senses.yml の 3/0/12/3 は KanaRing.crossing_count と一致）。
    - 問題は、この値がずれても検出されないことです。
  - `backfill:sense_metrics`（backfill.rake:23-29）にはテストがありません（test/ を `sense_metrics` で検索して0件）。lib/tasks/stats.rake と dev_samples.rake にもテストがありません（test/tasks にあるのは backfill_task_test.rb だけ）。
- 問題: CLAUDE.md:40-41 の手順（verify で差分を見て reading_metrics で直す）に従っても、円環交差数だけが古いまま残ります。そのため修復が済んだと誤認されます。
- 提案（計画書への提案に留めます。app と lib の変更を含むため）:
  - 読みから作る派生値を1箇所にまとめます（例: `WordSense.reading_derivations(reading)` が Hash を返し、コールバックと2つのタスクが共有する）。
  - ring_crossing_count を再生成と検証の両方に加えます。
  - backfill_task_test.rb に次のテストを足し、:41 のコメントを実態に合わせます。
    - ring_crossing_count を崩してから再生成と verify の報告を確かめるテスト
    - sense_metrics を崩してから元に戻ることを確かめるテスト
- 影響ファイル: lib/tasks/backfill.rake、app/models/word_sense.rb、test/tasks/backfill_task_test.rb
- リスク: 中（本番データを修復する手順に関わるため） ／ 外部振る舞いへの影響: なし（管理用タスクの出力だけが変わる）
- 先に必要な特性テスト: reading_metrics と verify の今の挙動は backfill_task_test.rb:12-48 で固定済みです。sense_metrics がつながっていることを確かめるテストを先に足します。

### [T-07] create! に渡した派生値は上書きされるので意味が無く、値自体も間違っている
- 観点: C・D ／ 確度: 確認済み
- 根拠:
  - test/models/word_request_duplicate_check_test.rb:71-72 `create!(reading: "べつのよみ", rhythm_pattern: "betsunoyomi", vowel_pattern: "euooi", mora_count: 6, last_char: "み")`。「べ・つ・の・よ・み」は5拍なので、6 は誤りです。
  - test/helpers/words_helper_test.rb の :68 `char_type_pattern: "漢漢"`、:69-70 `mora_count: 4`、:81 `char_type_pattern: "ア" * 12`、:84 `mora_count: 12`。
  - どれも before_validation で読み・表層形から作り直されます（WordSense#assign_reading_derivations。Word 側は test/models/word_test.rb:29-32 で上書きされることを確認済み）。
- 問題: 「create! にも派生値を渡すもの」「べつのよみ は6拍」と誤って覚えさせます。コールバックを通らないフィクスチャと、コールバックを通る create! の区別も曖昧になります。
- 提案:
  - これらの引数を削除します（setup の中なので期待値は変わりません）。
  - test_helper のコメントに次を書きます。「create! には派生値を渡さない。渡すのはフィクスチャと insert_all だけ」。insert_all の例は test/controllers/admin/words_controller_test.rb:144-145 です。
- 影響ファイル: test/models/word_request_duplicate_check_test.rb、test/helpers/words_helper_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です（各テストの既存の assert がそのまま守ります）。

### [T-08] 公開語の作り方が3通りあり、いちばん多い書き方は本番では起きない状態を作る
- 観点: B・E ／ 確度: 確認済み
- 根拠:
  - `Word.create!(..., annotated_at: Time.current)` だけで作る書き方が 24 箇所あります（annotation_status は既定の pending のまま）。
    - 例: test/controllers/words_controller_test.rb:154、test/models/word_ranking_test.rb:110、test/controllers/rankings_controller_test.rb:9
  - `annotation_status: :done` も渡す書き方が5箇所あります。
    - test/models/site_statistics_test.rb:27・63・145、test/controllers/stats_controller_test.rb:85、test/system/stats_vowel_graph_test.rb:11
  - `mark_annotated` を使うのは test/integration/words_feed_test.rb:59-65 と test/system/word_detail_mobile_test.rb:26 です。
  - 一方で app/models/word.rb:12 には「完了は annotated_at ありと一致する(mark_annotated が両方を立てる)」とあります。
- 問題:
  - 「公開済みなのに未対応」という本番に無い状態が、いちばん普通の書き方になっています。
  - アノテーションのキュー（annotation_pending）を扱うテストにこの語が混ざると、結果が変わり、原因も追いにくくなります。
  - どれを手本にすればよいかも決まっていません。
- 提案:
  - test_helper に `create_published_word(surface:, reading:, **sense_attributes)`（中で `mark_annotated` を呼ぶ）を置きます。
  - words_feed_test.rb:59-65 のヘルパをこれに置き換えて手本にします。
  - 既存の箇所は1ファイルずつ移します。
- 影響ファイル: test/test_helper.rb と、上に挙げた箇所を含むファイル
- リスク: 中（状態が done に変わるため、キューに関わるテストに混ざらないかを1件ずつ確認する必要がある） ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

### [T-09] システムテストの入力・クリックの手段がばらばらで、環境についてのコメントどうしが矛盾している
- 観点: A・B ／ 確度: コメントの矛盾は確認済み。現行の環境でどれが正しいかは推測（テストを実行していないため）
- 根拠:
  - 入力手段についての記述と実際の使い方が食い違っています。
    - test/system/admin_words_reading_format_test.rb:7（2026-07-13）は「この環境の chromedriver は日本語(CJK)の send_keys が入力欄に届かない(fill_in が空のまま)」と書いています。
    - ところが日本語の `fill_in` が test/system/word_request_form_test.rb:18・22・28 と admin_annotation_deck_test.rb:95 にあります。
    - `send_keys("日本文学", :enter)` も admin_annotation_console_test.rb:176・200 にあります（2026-08-18）。
    - さらに admin_word_candidates_test.rb:144-145（2026-09-25）は「ネイティブのキー入力がページに届かない(Actions も要素の send_keys も)」と書いています。
  - ヘルパを使わない生の JS クリックがあります。
    - admin_annotation_console_test.rb:130（`click_via_js` と同じ処理）
    - 同 :140
    - 同 :151 `window.confirm = () => true; arguments[0].click()`
    - test/application_system_test_case.rb:19-21 は「confirm の検証は click_accepting_confirm を使うこと」と定めています。
  - 共通化されていないローカルヘルパがあります。
    - admin_word_candidates_test.rb:119-151 の `click_row` と `click_table_row`（ほぼ同じ処理）、`press`
    - admin_words_reading_format_test.rb:9-14 の `type_japanese`
  - ウィンドウ幅の戻し方も2通りです。admin_annotation_console_test.rb:28-29 は ensure、word_detail_mobile_test.rb:9-11 は teardown で戻します。
- 問題:
  - 日本語の入力やキー操作をどう書けばよいか、エージェントは決められません。結果として、近くのファイル次第で壊れやすい書き方を選びます。
  - confirm を手書きでスタブすると、メッセージの取り違えを検出できません。
- 提案:
  - ApplicationSystemTestCase に次のヘルパを置きます。
    - `set_value_via_js(selector, text)`（type_japanese を移す）
    - `press_key(key, ctrl:)`
    - `dispatch_click(element, shift:)`
    - `with_window_size(w, h) { }`
  - 環境の制約についての説明は、ApplicationSystemTestCase に1回だけ書きます。文面は、test:system を実行してどの手段が通るかを確かめてから決めます。
  - ヘルパの使い分けを決めます。
    - 押し直しても結果が同じ操作 → click_expecting
    - 押し直すと困る操作 → click_via_js
    - turbo_confirm → click_accepting_confirm
    - トグル → 素のクリック（header_nav_menu_test.rb:5、search_char_type_test.rb:9 の方針）
  - console :151 を click_accepting_confirm に替えるのは、計画書への提案に留めます（検証が1つ増えるため）。
- 影響ファイル: test/application_system_test_case.rb と system テスト4ファイル
- リスク: 中（system テストは不安定になりやすい） ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。リファクタ後に test:system を何度か回して安定を確かめます。

### [T-10] CLAUDE.md の「システムテストは JS が無いと成立しない挙動だけ」が実態と合っていない
- 観点: A ／ 確度: 確認済み
- 根拠:
  - 規約は CLAUDE.md:206 です。
  - これに対し、JS ではなくレイアウトの検証をしているシステムテストがあります。
    - test/system/stats_vowel_graph_test.rb:5「checkbox + 兄弟セレクタの CSS だけで動く(JS を持たない)」
    - word_detail_mobile_test.rb:22（はみ出しの計測）
    - admin_annotation_console_test.rb:15（ボタンが右端にあること）
  - 逆に word_request_form_test.rb:10-15（検索0件の画面にリクエストへのリンクがあり、語が引き継がれる）はサーバで描画されるので、結合テストで書けます。
- 問題: 規約を文字どおりに読むと、正当なレイアウトの検証を消してしまうか、JS の要らない検証を system に書き足してしまいます。
- 提案:
  - CLAUDE.md:206 を「実ブラウザ（JS の実行・レイアウトの計算）が無いと確かめられない挙動だけに書く」に直します。
  - word_request_form_test.rb:10-15 のリンクと語の引き継ぎの部分は、結合テストへ移します。これは計画書への提案に留めます（テストを分割するため）。
- 影響ファイル: CLAUDE.md、test/system/word_request_form_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

### [T-11] キャッシュ・設定・ENV の差し替えがファイルごとの局所ヘルパで重複し、効いていない後始末もある
- 観点: B・C・E ／ 確度: 確認済み
- 根拠:
  - `Rails.cache` を差し替える `with_memory_cache` が、同じ中身で2つあります。
    - test/models/published_sense_counts_test.rb:46-52 と search_regexp_test.rb:64-70
    - 対象は app/models/published_sense_counts.rb:27 と search_regexp.rb:51 の `Rails.cache.fetch` なので、差し替える先は正しいです。
  - フラグメントキャッシュ用のヘルパは searches_controller_test.rb:160-169 の `with_fragment_cache` だけです。これが CLAUDE.md:208 に沿った正しい書き方です。
  - 設定を戻す書き方も揃っていません。
    - test/integration/indexing_switch_test.rb:34-39 は、ensure で元の値ではなく `true` に戻します。
    - word_requests_controller_test.rb:164-170 は元の値に戻します。
    - ENV は analytics_test.rb:31-37 の `with_env` です。
    - `allow_forgery_protection` は admin/words_controller_test.rb:224・248、`MorphemeFrequencies.path` は stats_controller_test.rb:108・116 と morpheme_frequencies_test.rb:4-5・16-20 で、それぞれ個別に戻しています。
  - 何もしていない処理があります。
    - test/system/stats_vowel_graph_test.rb:16・19 の `Rails.cache.delete(SiteStatistics::CACHE_KEY)` です。
    - テスト環境では config/environments/test.rb:29 が `:null_store` なので、何も消していません。
- 問題:
  - CLAUDE.md が警告している事故（Rails.cache だけ差し替えて、フラグメントキャッシュを一度も通っていなかった）を防ぐ共通の仕組みがありません。
  - 効いていない delete は、統計がテスト間で持ち越されると誤解させます。
- 提案:
  - test_helper に `with_rails_cache` / `with_fragment_cache` / `with_config(key => value)`（元の値に戻す）/ `with_env` を置き、各ファイルの局所的な定義を削除します。
  - stats_vowel_graph_test.rb の delete 2行を削除します。
- 影響ファイル: test/test_helper.rb と上に挙げた各ファイル
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

### [T-12] テスト名・メッセージと、実際に検証している内容がずれている
- 観点: A ／ 確度: 確認済み
- 根拠:
  - test/controllers/admin/words_controller_test.rb:325「単語を削除できる(語義・特徴も連鎖削除)」は、:333 で WordSense の削除しか見ていません。
  - test/models/word_sense_feature_test.rb:61「別の語義になら同じ特徴・同じ該当部分でも有効」は、:62-63 で該当部分に「カレー」を使っています。
    - これは既存の特徴（「殺人」「事件」）と同じ該当部分ではありません。
    - そのため、app/models/word_sense_feature.rb:21 の一意制約 `scope: [ :word_sense_id, :linguistic_feature_id, :target_start ]` から word_sense_id を外しても、このテストは通ります。
  - test/models/reannotation_export_test.rb:58「注釈済みの語でも…」が使っているのは、annotated_at の無い `words(:pending_haruhi)` です。
    - ここでの「注釈済み」は app/models/reannotation_export.rb:73-79 の private メソッド `annotated?`（意味などが1つでも付いている）の意味です。
    - Word.annotated（annotated_at がある）とは別の意味で、同じ言葉が2つの意味で使われています。
  - test/controllers/word_requests_controller_test.rb:5 は「重複の判定そのものはモデルのテストで見る」と書いています。
    - しかし :121-123 で判定規則（かなの違いを同一視する）を再検証しています。
    - これは test/models/word_request_duplicate_check_test.rb:21-26 と重複します。
  - test/models/morpheme_frequencies_test.rb:89 のメッセージは「朱にする最頻は1件だけ」です。朱のアクセントは CLAUDE.md:124 で廃止済みです。
  - test/models/tag_kind_test.rb:37 の `assert jp_history.persisted?` は、何も検証していません。
- 問題: テスト名を信じたエージェントは、特徴の連鎖削除や一意制約の範囲はすでに固定されていると誤認します。そのため、それを崩す変更をしても気づきません。
- 提案:
  - テスト名を中身に合わせます。
    - :325 →「単語を削除すると語義も消える」
    - :61 →「別の語義には同じ特徴を付けられる」
    - reannotation :58 →「注釈の内容が保存された語でも…」
  - 検証を強めた版は、新しいテストとして足します。
    - 単語を削除すると特徴も消えること
    - 同じ該当部分の「殺人」を別の語義に付けられること
  - morpheme のメッセージの修正と、tag_kind :37 の assert の削除は、計画書への提案に留めます。
- 影響ファイル: test/controllers/admin/words_controller_test.rb、test/models/word_sense_feature_test.rb、test/models/reannotation_export_test.rb、test/models/morpheme_frequencies_test.rb、test/models/tag_kind_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 検証を強めた版を足します。

### [T-13] 重複したテスト、役目を終えた「不在」の確認、ルート宣言そのものの確認
- 観点: B・C ／ 確度: 確認済み
- 根拠:
  - 完全に同じテストがあります。
    - test/models/word_sense_feature_test.rb:56-59 の `WordSenseFeature.new(valid_attributes(target: "事件", target_reading: "じけん")).valid?`
    - これは :10-12 の `WordSenseFeature.new(valid_attributes).valid?` と同じ式です（:6-7 の既定値が target "事件"、target_reading "じけん"）。
  - 廃止した機能の「不在」を確認しています。
    - test/models/related_words_test.rb:22-23「「同じ先頭文字」のグループは廃止した」の `assert(groups.none? ...)`
    - CLAUDE.md:207 の方針に反します。
    - 既報の pages_controller_test.rb:31 と同じテストにある :33 `.page-toc` も同じ種類です（このクラスはアプリに存在しません）。
  - ルート宣言そのものを確認しています。
    - test/controllers/words_controller_test.rb:371-379 の `assert_routing`
    - 「POST /words が無い」ことはセキュリティ上の不変条件ですが、PATCH・DELETE や他のリソースは見ていません。
  - 同じ振る舞いを2つの層で検証しています。
    - 除外（_exclude）の処理を、test/models/bulk_word_registration_test.rb:235-247 と admin/words_controller_test.rb:283-301 の両方が見ています。
- 提案:
  - word_sense_feature_test.rb:56-59 は削除します（:10-12 が同じ式を検証しています）。
  - related_words :22-23 と pages :33 の不在の assert を削除します。これは計画書への提案に留めます。
  - :371-379 は、admin_authentication_test と同じようにルート表から全件を調べるテストに置き換えます。確かめる内容は「admin/ 以外で GET 以外を受け付けるのは session と requests だけ」です。これも計画書への提案に留めます。
  - _exclude は規則を持つモデルの層を正とし、controller 側の assert の整理は計画時に決めます。これも計画書への提案に留めます。
- 影響ファイル: test/models/word_sense_feature_test.rb、test/models/related_words_test.rb、test/controllers/pages_controller_test.rb、test/controllers/words_controller_test.rb、test/models/bulk_word_registration_test.rb、test/controllers/admin/words_controller_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: ルート表から調べるテストを先に足してから、:371-379 を外します。

### [T-14] canonical ホストが6クラスに同じ定数として重複し、設定値との関係が書かれていない
- 観点: B・E ／ 確度: 確認済み
- 根拠:
  - `HOST = "https://nagai-kotoba-database.jp".freeze` が次の6箇所にあります。
    - test/integration/meta_tags_test.rb:5、structured_data_test.rb:6、words_api_test.rb:5、facet_indexing_test.rb:6
    - test/controllers/llms_controller_test.rb:6、sitemaps_controller_test.rb:5
  - words_controller_test.rb:260-261 はホストを直書きしています。
  - robots_controller_test.rb:12 だけが `Rails.application.config.x.canonical_host` を参照しています。
  - 既定値は config/application.rb:49 の `ENV.fetch("CANONICAL_HOST", ...)` で決まります。
- 問題: テストは CANONICAL_HOST が未設定であることを前提にしています。これを設定した環境では、これらのクラスが一斉に落ちます。どちらの書き方が正しいかも決まっていません。
- 提案:
  - test_helper に `CANONICAL_HOST = "https://nagai-kotoba-database.jp"` を1つ置きます。コメントには「本番の既定値を固定するためにリテラルで書く」と理由を書きます。
  - 各クラスの定数は削除します。
  - 1箇所で `assert_equal CANONICAL_HOST, Rails.application.config.x.canonical_host` を検証し、前提が崩れたときはそこだけで分かるようにします。
- 影響ファイル: 上の7ファイルと test/test_helper.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

### [T-15] ログインの書き方が混在し、使われていないヘルパとフィクスチャがある
- 観点: B・C ／ 確度: 確認済み
- 根拠:
  - `Admin.take` が 98 箇所・14 ファイルにあります。大半は各テストの先頭の `sign_in_as(Admin.take)` で、admin/annotations_controller_test.rb だけで 30 回あります。
  - `admins(:one)` は7つのテストファイルと `system_sign_in` の既定値（test/application_system_test_case.rb:131）で使われています。setup でログインしているのは admin/candidates/lists_controller_test.rb:5-7 などです。
  - フィクスチャの管理者は2人（test/fixtures/admins.yml:3-9）なので、`Admin.take` がどちらを返すかは決まっていません。
  - test/test_helpers/session_test_helper.rb:11-14 の `sign_out` は使われていません（`sign_out\b` で検索して定義だけ）。
  - admins.yml:7-9 の `two` も使われていません（`admins(:two)|admin_two` で検索してフィクスチャだけ）。
- 提案:
  - 正しい書き方を `setup { sign_in_as(admins(:one)) }` に統一します（手本は lists_controller_test.rb:5-7）。
  - `sign_out` と `two` を削除します。
- 影響ファイル: 管理系のテスト14ファイル、test/test_helpers/session_test_helper.rb、test/fixtures/admins.yml
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

### [T-16] 外部コマンドに依存するテストの skip の書き方が3通りある
- 観点: B・E ／ 確度: 書き方の違いは確認済み。neologd に依存するかどうかは推測
- 根拠:
  - 3通りの書き方があります。
    - test/services/morpheme_extractor_test.rb:6-9: setup で、サービス自身の `available?` を見て skip
    - reading_extractor_test.rb:5-7: テスト内で `system("mecab", "--version")` を書き直して skip
    - share_card_renderer_test.rb:54: クラスメソッドの `available?` を見て skip
  - reading_extractor_test.rb:5-7 の判定は、アプリ側 app/services/reading_extractor.rb:70-73 の private メソッド `mecab_available?` と重複しています。
  - reading_extractor_test.rb:20 は「テンジョウテンゲユイガドクソン」という厳密な読みを期待しています。これは neologd がある前提かもしれません（reading_extractor.rb:7-8・18-22）が、skip の条件は mecab の有無だけです。
- 提案:
  - 「サービスが公開している `available?` を見て skip する」を正しい書き方にします（手本は share_card_renderer_test.rb:54）。
  - ReadingExtractor に公開の `available?` を持たせるのは計画書への提案に留めます（アプリの変更になるため）。
  - 辞書に依存する厳密なテストをどう扱うかは計画時に決めます。
- 影響ファイル: test/services/reading_extractor_test.rb、test/services/morpheme_extractor_test.rb、app/services/reading_extractor.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: T-03 のフォールバックのテストを先に入れます。

### [T-17] 表示文言の検証が I18n.t の参照と直書きで混在し、422 を表す記号も2通りある
- 観点: B ／ 確度: 確認済み（件数は代表例だけ）
- 根拠:
  - 直書きしている例:
    - admin/annotations_controller_test.rb:45「提案付きの未対応語はありません」、:152、:164「立項 5/5」
    - admin/annotation_decks_controller_test.rb:61
    - admin/bulk_annotations_controller_test.rb:21・38
    - test/models/word_candidate_test.rb:78
  - 公開側の多くは `I18n.t` を使っています（例: words_controller_test.rb:65-69）。
  - 422 の記号: `:unprocessable_content` が3箇所、`:unprocessable_entity` が12箇所です。
    - `:unprocessable_content` の場所: candidates/triages_controller_test.rb:27、candidates/expansions_controller_test.rb:56、admin/word_candidates_controller_test.rb:36
- 提案:
  - 正しい書き方を「画面の文言は I18n.t で参照し、外部に出る文そのものだけを直書きで固定する」にします。直書きで固定する例は meta_tags_test.rb:41-42 のリード文です。
  - 直書きを参照に置き換えるのは、計画書への提案に留めます（assert の中身が変わるため）。
  - 422 の記号は、アプリ側の10箇所と一緒にどちらかへ統一します。
- 影響ファイル: test/controllers/admin/annotations_controller_test.rb など管理系のテスト数ファイル
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

### [T-18] ローカル変数 `words` が、フィクスチャのアクセサ `words(...)` を覆い隠している
- 観点: B ／ 確度: 確認済み
- 根拠:
  - test/system/admin_word_candidates_test.rb:72-73: 局所変数 `words = ...` の直後に `words(:curry)` を呼んでいます。
  - 同じことが test/models/annotation_research_export_test.rb:6・11、word_ranking_test.rb:85、word_batch_test.rb:29 にもあります。
- 問題: どちらの `words` を指すのか誤解しやすく、書き換えのときに壊しやすいです。
- 提案: 局所変数を `candidates` / `rows` などに改名します（期待値は変わりません）。
- 影響ファイル: test/system/admin_word_candidates_test.rb、test/models/annotation_research_export_test.rb、test/models/word_ranking_test.rb、test/models/word_batch_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

### [T-19] フィクスチャが本番データと違う点が、フィクスチャ側に書かれていない
- 観点: E ／ 確度: 確認済み
- 根拠:
  - test/fixtures/word_senses.yml:10 の murder の読みはひらがなですが、本番の読みはカタカナで統一されています。
    - この事実は test/models/word_sense_search_test.rb:62-63 のコメントにしか書かれていません。
  - ひらがなとカタカナの同一視（as_ci）に、明示せずに依存しているテストがあります。
    - 例: word_requests_controller_test.rb:121-123、shiritori_words_test.rb:48-56
  - 手書きの派生値（words.yml の char_type_pattern と、word_senses.yml の rhythm / vowel / mora / ring_crossing / last_char）は、手計算で全件が値オブジェクトの計算結果と一致することを確かめました。
- 提案: word_senses.yml の冒頭に次の注記を書きます。「murder の読みは、as_ci による同一視を検証するためにわざとひらがなにしている。実データはカタカナ」。
- 影響ファイル: test/fixtures/word_senses.yml
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要です。

---

## 1. この領域の正典パターン案
- **層の使い分け**
  - 変換・判定の規則は、値オブジェクトとモデルのテストで検証します。
  - 画面の出し分け・リンク・フォームの項目名は、結合テスト（assert_select）で検証します。
  - system テストは、実ブラウザ（JS の実行やレイアウトの計算）が必要なものだけにします（T-10）。
- **管理画面のテスト**
  - 結合テストは `setup { sign_in_as(admins(:one)) }` でログインします（手本: test/controllers/admin/candidates/lists_controller_test.rb:5-7）。
  - 未ログインの検証は書きません（test/integration/admin_authentication_test.rb にまとめてあります）。
  - system テストは `system_sign_in` を使います。
- **テストデータ**
  - 基本はフィクスチャを使います（公開2語・未対応2語・保留1語）。
  - 場面ごとに必要な公開語は、新設する `create_published_word`（mark_annotated を使う。今の手本は test/integration/words_feed_test.rb:59-65）で作ります。
  - create! に派生値は渡しません（T-07）。
- **外部に出る形式の固定**
  - JSON はキーの集合ごと `assert_equal` します（T-01）。
  - 一覧の並び順は `body_position` で比べます（手本: test/controllers/words_controller_test.rb:385-389）。
- **時刻**
  - 日付が関わるものは `travel_to Time.zone.local(...)`（手本: test/integration/published_words_digest_test.rb:24-33）を使います。
  - 経過時間が関わるものは `travel`（手本: test/controllers/sessions_controller_test.rb:40・54）を使います。
- **キャッシュ**
  - フラグメントは `with_fragment_cache`（手本: test/controllers/searches_controller_test.rb:160-169）を使います。
  - `Rails.cache.fetch` は `with_rails_cache`（手本: test/models/published_sense_counts_test.rb:46-52）を使います。
  - どちらも test_helper に移します。
- **設定と ENV**
  - `with_config` は元の値に戻す形にします（手本: test/controllers/word_requests_controller_test.rb:164-170）。
  - ENV は `with_env`（手本: test/integration/analytics_test.rb:31-37）を使います。
- **スタブと外部コマンド**
  - スタブは `stub_method`（test/test_helper.rb:22-28）を使います。
  - 外部コマンドを使うテストは、サービスの `available?` を見て skip します。
  - フォールバックは、`available?` を false にスタブして検証します。
  - 手本: test/integration/meta_tags_test.rb:50-61、test/controllers/words/share_cards_controller_test.rb:29-37、test/services/share_card_renderer_test.rb:54。
- **system テストの操作**
  - JS で操作する前に `wait_for_stimulus` で接続を待ちます。
  - 押し直しても結果が同じ操作は `click_expecting` を使います。
  - 押し直すと困る操作は `click_via_js` を使います。
  - turbo_confirm は `click_accepting_confirm` を使います。
  - トグルは素のクリックにします。
  - 隠れた選択肢は `choose_hidden_input`、`<details>` は `open_details` を使います。
  - 画面幅を変えるときは、新設する `with_window_size` を使います（T-09）。
- **文言**
  - `I18n.t` で参照し、外部に出る文そのものだけを直書きします（T-17）。
- **canonical ホスト**
  - test_helper の定数1つにまとめます（T-14）。

## 2. コードに表明すべき暗黙の前提
1. **環境変数が未設定であること**
   - CANONICAL_HOST が未設定であること（HOST 定数6箇所。T-14）。
   - REQUESTS_ENABLED・GA4_MEASUREMENT_ID・*_SITE_VERIFICATION も未設定を前提にしています（test/integration/analytics_test.rb:5-12）。
2. **インデックス解禁スイッチの既定値**
   - テスト環境では `indexing_enabled = true` です（config/environments/test.rb:68）。
   - 解禁前の挙動は indexing_switch_test だけが見ています。
3. **テスト環境のキャッシュは無効**
   - `perform_caching = false` かつ `:null_store` です（config/environments/test.rb:28-29）。
   - 差し替えない限り、キャッシュの経路は一度も通りません。
   - フラグメントキャッシュは `ActionController::Base.cache_store` に書かれます。
4. **フィクスチャはコールバックを通らない**
   - そのため派生値を手書きしています。
   - また、全テストの setup で `WordSenseMetrics.refresh!` を実行しています（test/test_helper.rb:14-18）。値オブジェクトだけのテストでも毎回走ります。
   - テスト内で作った語は、transactional test の中でも after_commit が動く前提です（同 :16-17）。
5. **照合順序**
   - 読み・表層形の比較は、MySQL 8 の `utf8mb4_0900_as_ci` を前提にしています。
   - その結果、ひらがなとカタカナは同一視され、清音と濁音は区別されます。
   - murder のひらがなの読みもこの前提に頼っています（T-19）。
   - MariaDB では成り立ちません（docs/overview.md §7）。
6. **外部コマンド**
   - 使うのは mecab と、rsvg-convert＋日本語の書体です。厳密な読みのテストは neologd がある前提かもしれません。
   - `ShareCardRenderer.available?` は、プロセスごとに1回だけ判定して結果を保持します（app/services/share_card_renderer.rb:26-29）。
7. **system テストのプロセス**
   - system テストのサーバは同じプロセスで動くので、`stub_method` が効きます（test/system/admin_words_reading_format_test.rb:25）。
   - ブラウザのウィンドウはテスト間で共有されます（word_detail_mobile_test.rb:7-8）。
8. **レートリミットのストア**
   - 重複チェックのレートリミットは、プロセス内のストアで数えます（app/controllers/word_requests_controller.rb:23）。
   - テストは setup でこのストアを空にしています（test/controllers/word_requests_controller_test.rb:8）。
9. **ワードクラウドの配置**
   - test/models/morpheme_cloud_test.rb:6-8 は、並列実行のフォーク前に、コミット済みの db/morpheme_frequencies.json から配置を計算します。
10. **日付に依存する表示**
    - 今日の一語と、ホームの月ごとの集計は `Date.current`（Tokyo）で決まります（T-05）。
11. **管理者の選び方**
    - `Admin.take` は、2人のフィクスチャのどちらを返すか決まっていません（T-15）。
12. **ジョブ**
    - ジョブは現在1つもありません（app/jobs は ApplicationJob だけ）。
    - そのため、:async のタイミングに依存するテストはありません。

## 3. コメントの傾向
- **量**: test/ の行頭コメントは 806 行、行末コメントは約 100 行です（grep で数えました）。
- **良い傾向**: 多くは Issue 番号や過去の事故を添えて「なぜ」を書いており、質は高いです（例: words_controller_test.rb:222-224、facet_indexing_test.rb:54-55・71-75）。
- **「何をしているか」だけのコメント**: 次の assert を言い換えただけのコメントは、概算で3割前後です（推測。全数は数えていません）。代表例:
  - test/controllers/words_controller_test.rb:12 `# 見出し語(surface)が詳細へのリンク`
  - test/controllers/words_controller_test.rb:272 `# ジャンル階層はパンくず(大→中→小)`
  - test/controllers/admin/words_controller_test.rb:29 `# 件数表示とページネーション`
  - test/controllers/admin/words_controller_test.rb:37 `# パネル(ジャンルピッカー・チップ・テンプレ文・注釈済みチェック)`
  - test/controllers/stats_controller_test.rb:13 `# 数字の壁は4群×5指標の定義リスト`
- **害の大きいもの**: 問題が大きいのは「何」を書いたコメントではなく、次の3種類です。
  - 環境についての知識を書いたコメントどうしの矛盾（T-09）
  - 中身の無い見出しの残骸（T-02）
  - 廃止した語彙の残り（T-12 の「朱」）

## 未確認のまま残した範囲（親が裏取りして埋める想定）
- テストを実行していないため、system テストでどの入力手段（日本語の fill_in / send_keys / JS での値の注入）が現行の Chrome で安定するかは分かっていません。T-09 の正典の文面はこの結果で決まります。
- 公開ページ（/words/:id・/genres・/browse・/stats・/rankings・/about）について、ビューの全要素と assert_select を突き合わせていません（主要な要素だけ確認しました）。
- /search フォームの13条件すべての name 属性と、既存の assert との照合をしていません。
- JSON API の実際の出力（ジャンルの無い語義で `genre: null` になるか、一覧の2ページ目）は確かめていません。テンプレートを読んだだけです。
- 画面文言を直書きしている assert の全数と、config/locales/ja.yml との一致は確かめていません（T-17 は代表例だけです）。
- lib/tasks/stats.rake・dev_samples.rake・db/seeds.rb にテストが無いことは確認しましたが、テストを足すべきかどうかは判断していません。
- transactional test の中で after_commit が動くという前提（test_helper.rb:16-17）は、Rails の既知の挙動に基づく判断です。コードでは裏取りしていません。
- ReadingExtractor の厳密な読みのテストが neologd を前提にしているかどうかは、辞書ごとの出力を確かめていないため分かっていません。
- 語義の無い公開語の詳細ページで、og:image のメタが何になるか（レイアウト側の分岐）は読んでいません。

### Critical Files for Implementation
- test/test_helper.rb
- test/application_system_test_case.rb
- test/integration/words_api_test.rb
- test/controllers/word_requests_controller_test.rb
- lib/tasks/backfill.rake（とセットで test/tasks/backfill_task_test.rb）

## 棚卸し（4610ead）

- 前提: `git diff a04f375..4610ead -- app config lib db test` は空。行番号はそのまま使える。
- **陳腐化: 0 件。**
- **重複**（計画書 §9 で同じ改修項目に束ねてある）:
  - T-06 ↔ M-01・CFG-02（backfill。C3-12）
  - T-15 ↔ M-15・C-16（未使用。R2-01）
  - T-01・T-03・T-04・T-05 ↔ 他の監査の「先に必要な特性テスト」（段階 0 の T0-01〜T0-04 に束ねてある）
- **要確認**:
  - T-09: system テストでどの入力手段が安定するか。オーナーの運用記録では「キー入力は JS で keydown を送る（ネイティブのキー入力はヘッドレス Chrome に届かない）」「confirm の検証は click_accepting_confirm」となっている。正典の文面は P-01 でこれを出発点にして決め、実行で確かめる。
  - T-16: ReadingExtractor の厳密な読みのテストが neologd を前提にしているかは未確認。C3-04 の着手前に、辞書ごとの出力を確かめる。
  - T-17: 文言の直書きの件数は代表例だけ。C3-11 で 1 件ずつ当たる。
- **未確認の範囲のうち、この棚卸しで決着したもの**:
  - transactional test の中で after_commit が動く前提（`test/test_helper.rb:16-17`）: `test/models/word_sense_metrics_test.rb:41` が、語義を作ったあとの `reading_density`（after_commit で焼き直す `max_reading_length` に依存する）を確かめていて、ベースライン（計画書 §1）では失敗 0 で通っている。**動いている**。
  - B-03 から預かった「test/integration・test/helpers が固定している data 属性」: `grep -rnoh 'data-[a-z-]*' test/integration test/helpers` は 0 件。data 属性はこの 2 か所では固定されていない。
  - B-04 から預かった「system テストが固定している CSS 上の性質」: `theme_toggle_test.rb:8-9` が body の地の色（ライト `rgb(255, 255, 255)`、ダーク `rgb(35, 41, 48)`）を、`word_detail_mobile_test.rb:34-53` が語義カードの横はみ出しと、ルビの上下 2 段積みを固定している。tokens.css の `--surface` / `--dark-surface` を変える項目は、このテストに当たる。
  - B-05 から預かった 3 点:
    - indexing_switch_test は `test/integration/indexing_switch_test.rb` にある（facet の分は `facet_indexing_test.rb`）。CFG-08 の解釈を変える件は §7.1 なので、中身の精読は要らない。
    - User-Agent の切り詰めのテストは**無い**（`word_requests_controller_test.rb:51` は短い値の一致だけ）。P-01 で段階 0 に足すかを決める。
    - system テストの Google Fonts の遮断（`application_system_test_case.rb:28`）は、下の T-20 にした。
- **新しい指摘**:
  - **[T-20] system テストが、もう読んでいない Google Fonts を遮断している**（観点: C・A ／ 確度: 確認済み）。
    `test/application_system_test_case.rb:26-28` は「Web フォント（Google Fonts）を読み込ませない」として、fonts.googleapis.com と fonts.gstatic.com を 127.0.0.1 に向けている。
    しかし `grep -rn 'fonts.googleapis\|fonts.gstatic' app config` は 0 件で、アプリは web フォントを読まない（CLAUDE.md「web フォントは読まない」）。
    コメントは、読み込む前提の理由を書いたまま残っている。消すか、コメントを「念のための保険」に直すかを P-01 で決める（消しても振る舞いは変わらない見込み。リスク 低）。
- **P-01 で決めること**: lib/tasks/stats.rake・dev_samples.rake・db/seeds.rb にテストを足すかどうか。この監査は「無い」ことしか確かめていない。
- **見送るもの**（特性テストを書く段階 0 で、書きながら突き合わせれば足りる）: 公開ページのビュー全要素と assert_select の突き合わせ、/search の 13 条件の name 属性、JSON API の実際の出力、語義の無い公開語の og:image のメタ。
