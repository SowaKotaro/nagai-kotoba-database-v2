> フェーズ1の監査報告（担当: app/controllers・app/helpers・app/views）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# 監査報告：controllers / helpers / views（routes は照合用）— ID プレフィクス C-

利用上限による2回の中断のあと、指示に従って重要項目に絞って仕上げました。コードは一切変更していません。テスト・DB・rake は実行しておらず、使ったのは `bin/rails routes` と読み取りだけです。作業ツリーの未コミットの変更（README.md・.claude/ 配下）には触れていません。

**問題がなかったこと（確認済み）**
- routes.rb とアクション、テンプレートは一致しています。ルートが無いアクションも、テンプレートが無いアクションもありません。
- 公開側で GET 以外を受けるのは session と requests（create / duplicates）だけです。例外は C-15 のエンジンのルートです。
- 管理側の認証は、ルート表を列挙するテスト（test/integration/admin_authentication_test.rb:10-20）で全アクションが固定されています。
- 公開条件はコントローラ全体で `Word.annotated` / `WordSense.published` に統一されています。生の `annotated_at` 条件は並び替えにしか出てきません。

---

## 指摘（重要度の高い順）

### C-01 検索条件の許可パラメータが2か所で別々に定義され、中身が食い違っている
- 観点: B/D ／ 確度: 確認済み（コードを読んで裏付け。動かしてはいない）
- 根拠:
  - words_controller.rb:133-144 は `:reading_length, :mora_count, … :vowel_transition, … :first_char, :last_char, :part_of_speech_id, :entity_type_id, :linguistic_feature_id` をスカラでも許可しています。
  - searches_controller.rb:35-42 は上のスカラ形と `reading_length` / `mora_count` / `vowel_transition` を許可していません。
  - 一方、words/index.html.erb:71 の「条件を変える」は `search_path(request.query_parameters.except("page"))` をそのまま渡します。
  - スカラ形の URL 自体は words_helper.rb:140-142（char_facet_words_path）と words/show.html.erb:191 `words_path(first_char: sense.first_char)` が生成しています。
- 問題:
  - /words?first_char=ア や ?part_of_speech_id=3 から /search へ移ると、条件が permit で黙って落ちます。
  - searches_controller.rb:33-34 のコメント「genre_id / word_origin_id は…両方許可」が、他のキーが欠けていることを隠しています。
  - 許可するキーの正が、WordSenseSearch#to_query_params（word_sense_search.rb:114-141）と2つのコントローラの計3か所に分かれています。
- 提案:
  - `WordSenseSearch::PERMITTED_PARAMS`（スカラ形と配列形の両方）を1つ作り、両コントローラは `params.permit(*WordSenseSearch::PERMITTED_PARAMS)` だけを使います。
  - 「to_query_params の全キーが PERMITTED_PARAMS に含まれる」ことを単体テストで固定します。
- 影響ファイル: words_controller.rb, searches_controller.rb, word_sense_search.rb
- リスク: 低 ／ 外部振る舞いへの影響: あり（/search?first_char=ア などでフォームに条件が残るようになる。不具合の修正）
- 先に必要な特性テスト: searches_controller_test.rb が試しているのは配列形だけです（:112-126）。スカラ形と reading_length / mora_count / vowel_transition を渡したときの /search の表示を追加してください。

### C-02 「語の読み・読みの長さ・代表の語義」の取り方が画面ごとに違い、並び順の指標と表示がずれる
- 観点: D/E ／ 確度: 確認済み（ずれが出るのは、先頭の語義が最長でない多語義語に限られる）
- 根拠:
  - home_controller.rb:41 `@longest_words.load.first&.word_senses&.first&.reading_length` です。コメントは「下の…1位と同じ値」と書いていますが、並び順は word_sort.rb:37 `words.max_reading_length DESC` で決まっています。
  - 各画面の取り方:
    - home/index.html.erb:205 `word.word_senses.first&.reading_length`
    - words/_entry_row.html.erb:7 `primary = word.word_senses.first`（:29 で文字数を表示）
    - words/show.html.erb:66 `headline_sense = @word.word_senses.first`
    - words/index.html.erb:33 `@words.flat_map(&:word_senses).max_by { … reading_length.to_i }`
  - 語義の並び順も揃っていません:
    - word.rb:3 `has_many :word_senses` には order がありません。
    - words_helper.rb:31 だけが `sort_by(&:id)` で並べ直します。
    - words/show.html.erb:83 と structured_data_helper.rb:86 は並べ直しません。
- 問題: 「代表の語義」も「語義の並び順」も定義が無く、preload が返す順番（MySQL 任せ）に暗黙に依存しています。
- 提案:
  - 語の読みの長さは焼き込み列 `words.max_reading_length` を正にします。
  - 語義の並び順は1か所で定義します（`has_many :word_senses, -> { order(:id) }` か `Word#ordered_senses`）。
  - 代表の語義は `Word#headline_sense` を作ってそこに集めます。ビューの `max_by` は消します。
- 影響ファイル: home_controller.rb, home/index, words/_entry_row, words/show, words/index, word.rb, words_helper.rb, structured_data_helper.rb
- リスク: 中 ／ 外部振る舞いへの影響: あり（多語義語で、ホームの数字・一覧の文字数・語義番号が変わりうる）
- 先に必要な特性テスト: 先頭の語義が短い2語義の語を用意し、ホームの看板・一覧の行・詳細の語義順・JSON の senses 順を固定してください。

### C-03 公開側の HTTP キャッシュが、ログイン状態で中身が変わる HTML にかかっている
- 観点: E ／ 確度: 確認済み（304 で古いヘッダーが残る点）／推測（共有キャッシュの有無はインフラ次第）
- 根拠:
  - public 指定でキャッシュさせている箇所: words_controller.rb:48 `stale?(etag: records, …, public: true)`（Atom は :29）
  - 同じ HTML にログイン状態で変わる部分がある箇所:
    - shared/_header.html.erb:70-73 の `authenticated?` 分岐で、管理リンクと `button_to …session_path, method: :delete`（CSRF トークン入りのフォーム）が出ます。
    - layouts/application.html.erb:6 の `csrf_meta_tags`
    - layouts/application.html.erb:154-158 のフッター
  - ETag に認証状態が入っていません（application_controller.rb:1-3 に `etag {}` がありません）。
  - 理由付けのコメントも取り違えています。word_requests_controller.rb:8-10 と words/index.html.erb:127 は「単語一覧は public: true の HTTP キャッシュ配下」と書いていますが、一覧の HTML にはキャッシュ宣言がありません（words_controller.rb:24）。public でキャッシュされているのは詳細ページのほうです。
- 問題:
  - 管理者がログインしても、ブラウザにキャッシュ済みの詳細ページは 304 になり、ログイン前のヘッダーのまま表示されます。
  - 共有キャッシュがあれば、管理者用の HTML が他の人に配られる可能性もあります。
- 提案（計画書への提案のみ。HTTP ヘッダーが変わるため）: 「public でキャッシュする HTML は利用者ごとの差分を持たない」という前提をコードに書きます。具体的には `etag { authenticated? }` を足すか、ログイン中は public にしないようにします。あわせて上の2か所のコメントを直します。
- 影響ファイル: application_controller.rb, words_controller.rb, word_requests_controller.rb, words/index.html.erb
- リスク: 中 ／ 外部振る舞いへの影響: あり（ログイン中の Cache-Control / ETag）
- 先に必要な特性テスト: 304 のテストは Atom の words_feed_test.rb:41-54 だけです。「ログイン前後で words#show の ETag が一致しない」ことを追加してください。

### C-04 キャッシュの書き方が3つの層に散らばり、TTL・キーの命名・同じ集計が重複している
- 観点: B/D/E ／ 確度: 確認済み
- 根拠:
  - コントローラで Rails.cache に置いているもの:
    - home_controller.rb:11 `"home/stats/#{…%Y-%m}", expires_in: 1.hour`（リテラル）
    - pages_controller.rb:6,9 `ABOUT_CACHE_TTL` / `"pages/about/word_count"`
    - llms_controller.rb:8,23 と sitemaps_controller.rb:15,20 がそれぞれ `CACHE_TTL = 1.day` を持っています。
  - モデルで持っているもの:
    - published_sense_counts.rb:8-12 は `CACHE_KEY "…/v1"`・TTL・RACE を揃えています。
    - ほかに site_statistics.rb:11-12,33-34、word_ranking.rb:59、search_regexp.rb:51、word_request_duplicate_check.rb:46
  - HTTP ヘッダーの宣言:
    - robots_controller.rb:8 `expires_in 1.day`（リテラル）
    - share_cards_controller.rb:18,20
  - 前提の結び付きがコード上に無い箇所:
    - published_words_digest.rb:14-15 は「どちらも expires_in 1.day」を前提にしていますが、TTL は各コントローラの定数です。
    - RACE の値も PublishedWordsDigest（1.minute）と PublishedSenseCounts（30.seconds）に分かれています。
  - `Word.annotated.count` が3通りに扱われています。ホームで1時間キャッシュ、About で1日キャッシュ、llms_controller.rb:43 ではキャッシュ無しです。
- 問題: 同じ種類のキャッシュを足すとき、どれを手本にすればよいかが決まりません。
- 提案:
  - 集計値のキャッシュは published_sense_counts.rb の形に揃えます（クエリオブジェクトのクラスメソッド＋`CACHE_KEY …/vN`＋TTL 定数）。
  - コントローラには HTTP の宣言（expires_in / stale?）だけを残します。
  - sitemap・llms-full の1日は `PublishedWordsDigest::TTL` に移します。
  - ホームと About の件数は C-09 の集計オブジェクトに移します。
- 影響ファイル: 上に挙げたコントローラ4本, published_words_digest.rb, published_sense_counts.rb
- リスク: 低〜中（キャッシュキーが変わるので、切り替え直後に1回だけ作り直しが走る）／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: test/integration/published_words_digest_test.rb はあります（中身は未精読）。キャッシュを検証するときは、CLAUDE.md のとおり ActionController::Base.cache_store を差し替えてください。

### C-05 絶対 URL の組み立てと canonical_host の参照が10か所以上に散らばっている
- 観点: B/D ／ 確度: 確認済み
- 根拠:
  - `config.x.canonical_host` を直接読んでいる箇所:
    - コントローラ: llms_controller.rb:32, robots_controller.rb:7, sitemaps_controller.rb:33
    - ヘルパ: application_helper.rb:77
    - テンプレート: words/index.json.jbuilder:2, words/show.json.jbuilder:2, words/index.atom.builder:2, words/_license.json.jbuilder:5, pages/about.html.erb:46
    - モデル: word_share_card.rb:127
  - URL の組み立て方が3流儀あります:
    - `"#{host}#{word_path(word)}"` を手で組み立てる形（json 2本, atom, sitemaps/show.xml.builder:14, llms/full.text.erb:41）
    - `absolute_site_url` ヘルパ（application_helper.rb:76-78）
    - パスを直書きする形（llms/show.text.erb:12-31 `<%= @host %>/words`）
  - `absolute_site_url` は private なのに、structured_data_helper.rb:5,14 などから使われています。
  - `"/og-default.png"` が2か所にあります（application_helper.rb:32, share_cards_controller.rb:6）。
  - 共有カードを焼けるかどうかの判定も2か所に重複しています（words_helper.rb:19-22, share_cards_controller.rb:28）。
- 提案:
  - `SiteUrl`（host / absolute(path) / DEFAULT_OG_IMAGE_PATH）を1つ作り、すべてここから取ります。
  - 焼けるかどうかの判定は `WordShareCard#renderable?` に集めます。
  - llms.txt ではルートヘルパを使います。
- 影響ファイル: 上に挙げたすべて
- リスク: 低 ／ 外部振る舞いへの影響: なし（出力される文字列は同一）
- 先に必要な特性テスト: words_api_test.rb:7-48, meta_tags_test.rb, sitemaps / llms / robots のコントローラテスト, share_cards_controller_test.rb:32 はあります（いずれも中身は一部しか確認していません）。

### C-06 1語の直列化（JSON・llms-full・JSON-LD）で、共通の部品を各所で手書きしている
- 観点: B/D ／ 確度: 確認済み
- 根拠:
  - ジャンルのパス（大 › 中 › 小）の作り方が多数あります:
    - `t("words.lead.genre_separator")` を使う: words_helper.rb:48, structured_data_helper.rb:144-146
    - `" › "` を直書き: llms/full.text.erb:57, tags_helper.rb:21, admin/bulk_proposal_approvals/show.html.erb:31
    - 独自のマークアップ: admin/annotations/_sense_fields.html.erb:88-90, _proposal_sense.html.erb:22-23, shared/_genre_path.html.erb
    - 配列で出す: show.json.jbuilder:19-27, reannotation_export.rb:100-103
  - ライセンスの URL と名前:
    - structured_data_helper.rb:80 `CC_BY_URL`
    - words/_license.json.jbuilder:3-4 `"CC BY 4.0"` と URL の直書き
    - pages/about.html.erb:42 の URL 直書き
    - ja.yml:1319 `license_name`
  - 派生値の説明文をモデルとは別に手書きしていて、すでにずれています。llms/full.text.erb:25 は「A=英字」としていますが、CharTypePattern は小文字の `a` を別の文字種にしています（char_type_pattern.rb:6,19）。
  - 属性の列挙順とラベルが3か所で別々です（show.json.jbuilder:9-43, llms/full.text.erb:47-73, structured_data_helper.rb:127-141）。
- 提案:
  - 出力形式ごとの直列化はそのまま残します（JSON 形式は変えない）。
  - 共通部品だけを1か所にします。`Genre#path_names` ＋区切り1つ、ライセンスの定数（URL・名前）、凡例は CharTypePattern の定数から作ります。
- 影響ファイル: 上に挙げたすべて
- リスク: 低 ／ 外部振る舞いへの影響: あり（llms-full の凡例1行を訂正）。それ以外はなし。
- 先に必要な特性テスト: words_api_test.rb:22,27, structured_data_test.rb, llms_controller_test.rb（未精読）

### C-07 Atom の published / id が Rails の既定のまま（created_at / request.host）になっている
- 観点: A/E ／ 確度: 確認済み（actionview-8.1.3.1 の atom_feed_helper.rb:182-189 を読んで確認）
- 根拠: words/index.atom.builder:9 `feed.entry(word, url: …, updated: word.annotated_at)` は `published:` も `id:` も渡していません。このため `<published>` は `record.created_at` に、`<id>` と feed 全体の id は `request.host` になります。一方、方針は「公開面の日付に created_at は使わない」です（home_controller.rb:17-18、docs/overview.md §4）。
- 提案（計画書への提案のみ）: `published: word.annotated_at` を渡し、id は canonical_host から作ります。
- 影響ファイル: words/index.atom.builder
- リスク: 低 ／ 外部振る舞いへの影響: あり（フィードの中身）
- 先に必要な特性テスト: words_feed_test.rb は published / id を検証していません。現状の値を先に固定してください。

### C-08 同じ名前の指標（ジャンル数・今月の新収録・収録語数）が画面ごとに別に定義されている
- 観点: D ／ 確度: 確認済み
- 根拠:
  - 「ジャンル数」の定義が3通りあります:
    - ホーム（home_controller.rb:15）は `Genre.small.count` で、小分類をすべて数えます。
    - /genres（genres/index.html.erb:18,25）は `@published_counts.size` で、これは published_sense_counts.rb:22 の `group(:genre_id).count` です。genre は optional（word_sense.rb:10）なので、ジャンル無しの語義があると NULL のグループも1件と数えます。
    - /stats（site_statistics.rb:120）は `where.not(genre_id: nil).distinct.count(:genre_id)` です。
  - genres/index.html.erb:21-22 のコメント「ホームの『ジャンル数』と同じ定義に揃える」は事実と違います。
  - 「今月の新収録」は home_controller.rb:19 と site_statistics.rb:119 に同じ式をコピーしています。
  - 「収録語数」は home, pages, llms, SiteStatistics の4か所でそれぞれ数えています。
- 提案（定義の決定が要るので計画書への提案）: オーナーが定義を決め、集計オブジェクトを1つ作って全画面から呼びます（例: PublishedSenseCounts に `word_count` / `genre_count` / `monthly_new_count` を足す）。
- 影響ファイル: home_controller.rb, pages_controller.rb, llms_controller.rb, genres/index, published_sense_counts.rb, site_statistics.rb
- リスク: 中 ／ 外部振る舞いへの影響: あり（表示される数値）
- 先に必要な特性テスト: 「ジャンル無しの公開語義」と「公開語の無い小分類」をフィクスチャに入れ、3画面の数値を固定してください。

### C-09 ページネーションの計算とマークアップが3組ずつ複製されている
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 計算は3つのコントローラに同じ形で書かれています。`PER_PAGE = 100`、`@page = [ params[:page].to_i, 1 ].max`、`@total_pages = [ (…/ PER_PAGE).ceil, 1 ].max`、`.limit(PER_PAGE).offset(…)` です（words_controller.rb:5,12,75-80、admin/words_controller.rb:4,20-28、admin/word_requests_controller.rb:7,14-20）。
  - マークアップも3か所です。words/_pagination.html.erb のほか、admin/words/index.html.erb:141-153 と admin/word_requests/index.html.erb:91-103 に直接書かれていて、管理側は公開側の `t("words.pagination.*")` を借りています。
  - words/index.html.erb:86 はビューから `WordsController::PER_PAGE` を参照しています。
- 提案:
  - 値オブジェクト `Pagination`（page / total_count / total_pages / offset / apply(scope)）を作ります。
  - パーシャルは `shared/_pagination` 1本にし、パスを作るラムダと nofollow / アイコンの有無を引数で受けます。HTML は現状と同一に保ちます。
- 影響ファイル: 上に挙げたコントローラ3本とビュー3本
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 管理一覧は admin/words_controller_test.rb:149-153 で固定済みです。公開一覧のページ送り（seed の引き継ぎと nofollow）は未確認なので、追加を推奨します。

### C-10 50音表とヒートの描画が3か所に複製されていて、KANA_COLUMNS が SearchesHelper にある
- 観点: B/D ／ 確度: 確認済み
- 根拠:
  - 表の定義は searches_helper.rb:4-22 にあり、3つのビューが `SearchesHelper::KANA_COLUMNS` として参照しています（browse/index.html.erb:17, searches/_kana_grid.html.erb:7, stats/_kana_heatmap.html.erb:7）。
  - browse/index.html.erb:16-41 と stats/_kana_heatmap.html.erb:6-29 はほぼ同じ内容です。違うのは i18n キーとパラメータ名だけです。
  - ヒートの濃さの計算もビューごとに書かれています（browse:25, :54、stats/_kana_heatmap:13）。
  - 一方、行の定義を持つモデル KanaRow はすでにあります（kana_row.rb:23）。
- 提案: 表の定義は概念の持ち主である KanaRow（または KanaTable）に移します。ヒートの描画は `shared/_kana_heatmap` 1本にし、濃さの計算は `heat_fill(count, max)` ヘルパにします。
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: browse と stats のコントローラテストはあります（中身は未精読）。

### C-11 コントローラに業務ロジックがあり、「新着順」などの規則が重複している
- 観点: B/D ／ 確度: 確認済み（最後の管理側の絞り込みだけ推測）
- 根拠:
  - 「今日の一語」の選び方がコントローラにあります（home_controller.rb:48-57 `offset(Date.current.jd % @word_count)`）。
  - 「新着順」の定義が3か所です。home_controller.rb:30 と words_controller.rb:108 の `order(annotated_at: :desc, id: :desc)`、それに word_sort.rb:25 の `"created_desc"` です。同じホームで最長の語は `WordSort` を使っている（:35）ので、書き方も揃っていません。
  - words_controller.rb:116-121 の `feed_cache_records` は `Word#cache_dependencies`（word.rb:54-60）の一部を別に書き直しています。
  - `AnnotationProposal.find_by(word_id: @word.id)` が4回出てきます（annotations_controller.rb:30,49,79,94）。スティッキー引き継ぎのセッション処理もコントローラにあります（:146-183）。
  - 推測: admin/words_controller.rb:123-134 はコメントで「公開検索と同じ意味論」と書きながら、ジャンルを配下に広げる処理を WordSenseSearch とは別に実装しています。CLAUDE.md の「同じ規則を2画面が名乗るなら定義は1箇所」に反している疑いがあります（意味が完全に一致するかは未検証）。
- 提案:
  - `Word.featured_on(date)` を作ります。
  - 新着順は `WordSort.new("created_desc").order_clause`（またはスコープ）に統一します。
  - Atom 用の依存レコードは `Word#feed_cache_dependencies` として cache_dependencies の隣に置きます。
  - 提案の取得は before_action にまとめます。
  - ジャンルを配下に広げる処理は WordSense のスコープ1つにして、公開検索と管理一覧の両方から使います。
- リスク: 低〜中 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 並び順は words_feed_test.rb:5-20 で固定済みです。今日の一語と管理側のジャンル絞り込みは要追加です。

### C-12 公開条件の名前が2つある（annotated と published）
- 観点: A/B ／ 確度: 確認済み
- 根拠:
  - 語は word.rb:20 の `scope :annotated`、語義は word_sense.rb:56 の `scope :published` です。周辺のクラスは PublishedSenseCounts / PublishedWordsDigest という名前です。
  - word.rb:13 のコメントは「annotated / published スコープ」と書いていますが、Word に published スコープはありません。
- 問題: 「published」で探したエージェントは、語の公開条件にたどり着けません。
- 提案: `Word.published`（annotated の別名）を足して公開側はそれを使うか、対応関係を1か所に明記します。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### C-13 状態のラベルとタブ、マスタ一式の読み込みの書き方が画面ごとに違う
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 状態のタブの作り方が揃っていません:
    - admin/words/index.html.erb:57-60 は状態をリテラルのハッシュで書いていて、admin/words_controller.rb:7 の `STATUS_FILTERS` と重複しています。
    - admin/word_requests/index.html.erb:7-8 は enum から作っています。
  - 登録予定単語の状態ラベル:
    - ヘルパ `candidate_status_label`（word_candidates_helper.rb:60-62）があります。
    - それなのにコントローラは `t("admin.word_candidates.statuses.#{…}")` を自分で組み立てています（candidates/base_controller.rb:38,50, lists_controller.rb:28, triages_controller.rb:50）。
  - マスタ一式の読み込みが3か所です。annotation_queue.rb:84-90 と admin/words_controller.rb:137-144 は名前順、searches_controller.rb:24-30 は id 順です。
- 提案:
  - タブは定数か enum から作ります。
  - ラベルは enum ごとに1メソッドにして、コントローラからもビューからもそれを呼びます。
  - マスタの読み込みは1か所にします。既存の annotation_masters.rb を流用できるかもしれません（未読なので推測）。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### C-14 アノテーション・キューの絞り込み UI が2つのビューに複製され、生の params と文字列リテラルで判定している
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 同じ UI が admin/annotations/show.html.erb:20-35 と admin/annotation_decks/_deck.html.erb:33-47 にあります。どちらも `params[:proposed]` / `params[:review] == "1"` / `params[:sort] == "easy"` で判定しています。
  - 同じリテラルが annotation_queue.rb:55-61 にもあります。
  - `proposed_param`（annotation_queue.rb:68-70）がすでにあるのに、ビューはそれを使っていません。
- 提案: パーシャル `admin/annotations/_queue_filter` を作り、`Admin::AnnotationQueue::SORTS` と helper_method（`queue_sort` / `review_filter?`）を足します。
- リスク: 低 ／ 外部振る舞いへの影響: なし（管理画面のみ）

### C-15 Strong Parameters と認証開放の書き方が揺れている
- 観点: B/E ／ 確度: 確認済み
- 根拠:
  - コントローラ全体での件数は、`params.require().permit` 10、`params.permit` 9、`params.fetch` 1、`params.expect` 0、生の `params[:x]` 60 です。
  - 認証開放の書き方:
    - word_requests_controller.rb:12 は `allow_unauthenticated_access` に `only:` が付いておらず、全アクションが開放されます。
    - 他の公開コントローラは `only:` 付きです（例: browse_controller.rb:4）。
  - 同じコントローラの中でも揃っていません: word_requests_controller.rb:72 は `require(:word_request)`、:77 は `fetch(:word_request, {})` です。
  - ID の配列の受け方が2通りです: admin/word_requests_controller.rb:26 は `where(id: params[:item_ids])` と生のまま、candidates/lists_controller.rb:22 は `params.permit(candidate_ids: [])` です。
  - その他の受け方:
    - 任意のハッシュを許可: candidates/base_controller.rb:43 `params.permit(decisions: {})`
    - admin/words_controller.rb:36 `params.permit(:text)[:text]`
    - 貼り付け JSON を生で受ける: annotation_proposals_controller.rb:52, candidates/base_controller.rb:12
  - 規約との関係: CLAUDE.md（セキュリティ節）は `require(...).permit(...)` を必須としています。
- 提案:
  - 使い分けを正典として決めます。モデルに渡す属性は `require(...).permit(...)`（手本: word_candidates_controller.rb:30-32）、ID の配列は `params.permit(ids: [])`、絞り込みのスカラは1つのメソッドで受けます。Rails 8 の `params.expect` に寄せるなら、CLAUDE.md の改訂が必要です。
  - WordRequestsController は `only: %i[new create duplicates]` にします。
- リスク: 低 ／ 外部振る舞いへの影響: なし（受け付けるキーは同じ。ただしキーが無いときの応答が require は 400、fetch はそのまま、と違うので、アクションごとに維持すること）
- 先に必要な特性テスト: admin_authentication_test の公開側版として、「公開側の GET 以外のルートは session と requests だけ」であることを固定してください。

### C-16 使われていないコード（残骸）
- 観点: C ／ 確度: 確認済み
- 根拠と、未使用と判定するために検索した内容:
  - app/helpers/articles_helper.rb:1-2 は空のモジュールです。初期コミット 5892612 の scaffold の残り（articles テーブルは作成後に drop 済み）で、参照は定義だけです。
  - アイコン shared/icons/_crown.html.erb と _sparkle.html.erb は最後の使用が ee7a328 で消えています。検索したのは次のとおりで、いずれも0件でした。
    - `icon "…"` の直接呼び出し
    - 動的に渡るアイコン名（WordRanking word_ranking.rb:21-35、AdminSection admin_helper.rb:35-40、_number_wall）
    - リポジトリ全体での単語検索
  - layouts/mailer.html.erb と mailer.text.erb: メーラーは ApplicationMailer しかなく、`deliver_` は0件です。
  - config/locales/en.yml:31 は `hello` だけです。application.rb:45 は `available_locales = %i[ja en]` としていますが、ロケールを切り替える箇所も `t("hello")` も0件です。
  - i18n キー ja.yml:967 `admin.annotations.nav` と :968 `admin.annotations.today` が未使用です。判定方法は次の3つです。
    - ja.yml の全ての葉キー名を app・lib・config で単語一致検索（0件はこの2件と、動的に組み立てられるキー・Rails 既定キーだけ）
    - 動的に組み立てるキー `t("…#{…}")` を全件一覧にした（`admin.annotations.#{…}` は無し）
    - 2階層目のキーを、相対キー `.key` を含めて照合した
  - `require "rails/all"`（application.rb:3）のため、`bin/rails routes` に公開の POST `/rails/active_storage/direct_uploads` と `/rails/action_mailbox/*/inbound_emails` が出ています。db/schema.rb にはそのテーブルがありません。
  - sessions/new.html.erb:8 の `value: params[:username]` は、create がリダイレクトする（sessions_controller.rb:13）ので値が入ることはありません。generator の残りです。
- 提案: 削除します。エンジンの件（フレームワークを明示的に require してルートを消す）だけは、計画書への提案のみにします。
- リスク: 低 ／ 外部振る舞いへの影響: なし（エンジンのルートを消す場合のみあり）

### C-17 ビューの中で規則・派生値・マジックナンバーを計算している
- 観点: D ／ 確度: 確認済み
- 根拠:
  - インデックス可否の規則がビューにあります（words/index.html.erb:21-22）。関連する規則は helper（words_helper.rb:121-134）と model（word_sense_search.rb:155-158,185-193）にもあり、3層に分かれています。
  - genres/index.html.erb:36-37 の `bar_width` は `20 + … * 80.0` を直書きしていますが、これは RadialChart::MIN_RATIO = 0.2（radial_chart.rb:16,33）と同じ写像です。
  - searches/index.html.erb:43,46,49 のスライダーは `10` / `30` を6か所に直書きしています。それぞれ WordSense::MIN_READING_LENGTH（word_sense.rb:33）と SiteStatistics::DISTRIBUTION_OVERFLOW_MIN（site_statistics.rb:147）を参照すべき値です。
  - 保存前の読みの長さを各所で数えています: admin/word_requests/index.html.erb:60 `item.reading.length`、admin/words/duplicates.html.erb:38、bulk_word_registration.rb:44
  - ホームは `RANKING_LIMIT = 10`（home_controller.rb:6）件読み込み、ビューで `take(5)`（home/index.html.erb:198）しています。
  - stats/index.html.erb:69-71 に `last(26)` / `last(13)` の直書きがあります。
  - 統計のワードクラウドは、データの出どころがコントローラを通っていません。stats/_word_cloud.html.erb:8-9 と stats/index.html.erb:19 が MorphemeFrequencies / MorphemeCloud を直接呼んでいます。
- 提案:
  - インデックス可否は `WordsHelper#indexable_index_page?` 1つにまとめます。
  - 横棒の写像は RadialChart の比率を使い回します。
  - スライダーの上下限は定数を参照します。
  - 保存前の読みの長さは1か所（例: WordRequestItem#reading_length）で数えます。
  - `RANKING_LIMIT` は 5 にします。
  - 統計の期間の切り方とワードクラウドの組み立ては SiteStatistics が返すようにします。
- リスク: 低 ／ 外部振る舞いへの影響: なし（値が同一なら）

### C-18 「管理画面かどうか」の判定と、管理画面への入口が3通りある
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 判定方法が2種類、3か所です:
    - パスで判定: layouts/application.html.erb:90（body のクラス）と shared/_header.html.erb:71（現在地の表示）が `request.path.start_with?("/admin")` を使います。
    - コントローラの型で判定: admin_helper.rb:8-10 は `controller.is_a?(Admin::BaseController)` を使います。
  - 入口のリンク先が2通りです: ヘッダーは admin_root_path（_header:71）、フッターは admin_words_path（application.html.erb:155）です。
- 提案: 判定は `admin_page?` に統一し、design.md §10 の記述も合わせて直します。フッターのリンクは admin_root_path にします。
- リスク: 低 ／ 外部振る舞いへの影響: ほぼなし（ログイン中のフッターのリンク先だけ）

### C-19 フラッシュが二重に表示される画面がある（「一元表示」の例外）
- 観点: B ／ 確度: 確認済み
- 根拠: layouts/application.html.erb:102-104 は「各ビューでは表示しない」としていますが、admin/words/new.html.erb:7-9 と readings.html.erb:7-9 は `flash.now[:alert]` を本文にも出しています。このため同じ警告が2回表示されます。
- 提案（計画書への提案のみ）: 既存テスト（admin/words_controller_test.rb:180,216 の `assert_select "p.form-alert"`）が現状を固定しています。例外としてコメントで明記するか、オーナーの判断でテストの期待値を変えるかのどちらかです。
- リスク: 低 ／ 外部振る舞いへの影響: なし（管理画面のみ）

### C-20 マスタを新しく作る経路が3つある
- 観点: B ／ 確度: 推測（ProposedMasterCreation とモデル側の正規化は未読）
- 根拠:
  - その場追加（inline_master_creatable.rb:17-43）は、前後の全角空白を落とし、ai_ci で衝突したときに理由を返します。
  - タグ管理（tags_controller.rb:19-29,87-89）は `@kind.model.new(tag_params)` で、コントローラ側では正規化していません。
  - 提案の新設候補（annotations_controller.rb:82, annotation_decks_controller.rb:76 から ProposedMasterCreation）
- 問題: 名前の正規化や重複時の扱いが経路によって違う可能性があり、変えるときは3か所を見る必要があります。
- 提案: 正規化と重複の方針をモデル（before_validation）かサービス1つに集めます。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### C-21 i18n の使い方が揺れている
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 相対キーと絶対キーが混在しています（word_requests/new.html.erb:1 `t(".title")` と _rows.html.erb:12 `t("word_requests.new.remove_row")`）。管理画面が `words.pagination.*` を借りています。
  - 同じ概念の名前空間が2つあります（ja.yml:489 `admin.word_candidates` と :618 `admin.candidates`）。コントローラ名・ルート・ナビのキーでも candidates と word_candidates の2つの名前が並存しています。
  - ハードコードされた文言:
    - llms/show.text.erb と full.text.erb は本文のほぼ全部（約40行）
    - admin/annotations/_sense_fields.html.erb:34「韻 / 母音 / モーラ」
    - admin/annotations/show.html.erb:38 と reresearch.html.erb:6 の「NO.」
    - searches/index.html.erb:21,101 のプレースホルダ
    - _license.json.jbuilder:3 の "CC BY 4.0"
    - llms を除くと約10か所です。
  - 区切り記号: ja.yml:385-386 に `metrics_separator` と `genre_separator` がありますが、「、」（6か所）、「・」（3か所）、「 › 」（3か所）が直書きされています。
- 提案:
  - テンプレート自身の文言は相対キー、共有パーシャルは自分の名前空間の絶対キーにします。
  - 区切り記号も i18n（または定数）にします。
  - llms のテンプレートを i18n の例外にするかどうかを CLAUDE.md で決めます。
- リスク: 低 ／ 外部振る舞いへの影響: なし（文字列が同一なら）

### C-22 小さな書き方の揺れ
- 観点: B/E ／ 確度: 確認済み
- 根拠:
  - 422 のステータスの書き方: `:unprocessable_entity` が7ファイル10か所、`:unprocessable_content` が3か所（candidates/base_controller.rb:17, triages_controller.rb:14, word_candidates_controller.rb:20）です。Rack は 3.2.6（Gemfile.lock:216）です。
  - 日付の書式: `l(…, format: :short)` が2か所（home/index.html.erb:177 ほか）、`strftime` が6か所（admin/words/index.html.erb:114, admin/word_requests/index.html.erb:64, stats/index.html.erb:9,12, stats/_timeline_chart.html.erb:20-21）です。
  - JSON の埋め込み: structured_data_helper.rb:10 と stats/_genre_sunburst.html.erb:9 `raw ERB::Util.json_escape` で書き方が違います。
  - ビューからコントローラの定数を参照しています（words/index.html.erb:86, word_requests/new.html.erb:31-32）。
  - words_helper.rb:123-133 のローカル変数 `params` が、リクエストの params を隠しています。
  - インラインスクリプトの nonce: テーマ用は `nonce: true`（application.html.erb:63）、GA 用は nonce 無し（_analytics.html.erb:6）です。CSP は無効（content_security_policy.rb:7-25 が全部コメントアウト）です。
  - rate_limit の保存先: sessions_controller.rb:3 は既定の Rails.cache を使います。test / dev では null_store なので制限が効きません。word_requests_controller.rb:18-28 は専用の MemoryStore を持っていて、理由も書いてあります。
- 提案:
  - 422 は `:unprocessable_content` に揃えます。テストの期待値（422）は変わりません。
  - 日付は `l()` に揃えます。
  - 定数は概念の持ち主（モデルや値オブジェクト）へ移します。
  - ローカル変数 `params` は改名します。
  - nonce は揃えるか、「CSP 無効が前提」とコメントで明記します。
- リスク: 低 ／ 外部振る舞いへの影響: なし（日付の表示形式を変えるなら、あり）

### C-23 コメントとコードの食い違い（別の担当と重複しうるので要点だけ）
- 観点: A ／ 確度: 確認済み
- 根拠:
  - home_controller.rb:26-27 の「words#feed」は存在しません（実体は words#index の atom 形式）。
  - words/index.html.erb:3 が挙げるファセットは、word_sense_search.rb:155-158 より少ないです（末尾文字・文字数・モーラ数・特徴が抜けている）。
  - home/index.html.erb:21-23 は古いコメントと新しいコメントが並んでいます。
  - 「太字」と書いているコメント（shared/_genre_path.html.erb:2, rankings/_board.html.erb:2, stats/_number_wall.html.erb:2）は、CSS が 400 なので事実と違います。
  - 統計のパーシャルが「アクセント」と書いています（_length_chart:2, _origins:3, _sound_breakdown:3, _timeline_chart:2-3）が、実際に使っているのは `--chart` です。
  - stats_helper.rb:356 は「2周期」ですが、コードは `WAVE_CYCLES = 1`（:22）、docs/stats.md:18 も「1周期」です。
  - shared/_header.html.erb:1 の「印章ロゴ」は、破棄した「紙とインク」デザインの名残です。

---

## 1. この領域の正典パターン案

| 処理 | 正典 | 手本 |
|---|---|---|
| 認証の開放 | 公開コントローラは必ず `allow_unauthenticated_access only: %i[…]` を付ける。管理は Admin::BaseController を継承するだけ | browse_controller.rb:4、admin/base_controller.rb（担保: admin_authentication_test.rb） |
| Strong Parameters | モデル属性は `require(:x).permit`。複数の画面で共有する集合は定数に1つ | word_candidates_controller.rb:30-32、Admin::AnnotationQueue::WORD_ATTRIBUTES（annotation_queue.rb:13-21）。検索条件は C-01 の `WordSenseSearch::PERMITTED_PARAMS` |
| 公開条件・並び | `Word.annotated` / `WordSense.published` だけを使う。並びは WordSort の定数 | word_sort.rb。新着も `"created_desc"` を使う |
| 集計のキャッシュ | クエリオブジェクトのクラスメソッド＋`CACHE_KEY …/vN`＋TTL 定数 | published_sense_counts.rb |
| 全件出力の HTTP キャッシュ | 日単位の版＋条件付き GET＋本文のキャッシュ | sitemaps_controller.rb:17-25 ＋ concerns/published_words_digest.rb。TTL は Digest 側へ |
| 詳細ページの条件付き GET | 依存レコード一式から ETag を作る | words_controller.rb:47-48 ＋ Word#cache_dependencies |
| 絶対 URL | `SiteUrl`（C-05）1つ | application_helper.rb:76-78 を公開して流用 |
| ページネーション | `Pagination` ＋ `shared/_pagination` | 見た目は words/_pagination.html.erb |
| 関連データの表示 | ジャンルはパーシャル、パンくずは JSON-LD と同時に出す | shared/_genre_path、shared/_breadcrumbs ＋ breadcrumb_json_ld |
| 文字の軸のリンク | スカラ形に揃える | char_facet_words_path（words_helper.rb:140） |
| ヘルパとパーシャルの境目 | 値・属性・文字列を返すならヘルパ、マークアップのまとまりならパーシャル | ヘルパ: reading_counter_data（word_requests_helper.rb）、パーシャル: shared/_genre_path |
| ヘルパでの DB アクセス | 原則引かない。引くときはメモ化して名前で示す。コントローラで先読みして渡す | 引いている現状の箇所: admin_helper.rb:50, word_candidates_helper.rb:42, searches_helper.rb:84, words_helper.rb:81 |
| i18n | テンプレート自身は相対キー、共有パーシャルは自分の名前空間の絶対キー。区切り記号も i18n | — |
| フラッシュ | レイアウトの #flash だけに出す | 例外は C-19 |
| 同じ規則を名乗る2画面 | concern か定数で1か所に置く | concerns/admin/annotation_queue.rb |

## 2. コードに表明すべき暗黙の前提の一覧

1. public でキャッシュする HTML（words#show と Atom）は、利用者ごとの差分（ログイン中の表示・CSRF トークン）を持たない（C-03）。
2. 語義の並び順は preload の返却順任せで、「代表の語義」は `word_senses.first` になっている（C-02）。
3. 日単位の版（PublishedWordsDigest）と、各エンドポイントの Cache-Control の1日が一致している（published_words_digest.rb:14 と各 CACHE_TTL）。
4. キャッシュストアは :memory_store で、worker 間で共有されない。sessions の rate_limit は、test / dev の :null_store では効かない（sessions_controller.rb:3）。
5. 照合順序の前提がコメントにしか書かれていない:
   - words_helper.rb:86-101,148-154 は as_ci を Ruby 側で近似している。
   - inline_master_creatable.rb:7-9 は ai_ci での衝突を前提にしている。
   - admin/word_requests_controller.rb:45-51 は as_ci での一致を前提にしている。
   - いずれもテストでは担保されていない。
6. 共有カードを焼けるかどうか（rsvg-convert の有無）の判定が、ヘルパとコントローラの2か所にある（words_helper.rb:19-22 / share_cards_controller.rb:28）。
7. Candidates::BaseController#run_import は、サブクラスに `load_stage` と show テンプレートがあることを前提にしている（candidates/base_controller.rb:11-17）。
8. 「annotation_done? なら annotated_at は必ずある」という不変条件に依存している（admin/words/index.html.erb:113-114 `word.annotated_at.strftime`）。
9. GA のインラインスクリプトは CSP が無効であることを前提にしている（_analytics.html.erb:6）。
10. 検索スライダーの 10 / 30 は、収録基準と統計の上限にひもづいている（C-17）。

## 3. コメントの傾向

- 大半は「なぜ」（Issue 番号・実測値・オーナーの指示）を述べています。「何をしているか」だけのコメントは、目視した範囲の印象で2割前後です（数えてはいません）。代表例:
  - admin/words/index.html.erb:142 `<%# 検索・絞り込み条件を保持したままページ送りする %>`
  - admin/word_requests/index.html.erb:92 `<%# 絞り込み条件を保持したままページ送りする %>`
  - stats/index.html.erb:27 `<%# 数字の壁: 4群×5指標の定義リスト %>`
  - admin_helper.rb:56 `# 現在地に aria-current="page" を付けた共通ナビのリンク。`
  - admin/words_controller.rb:146 `# step1 の入力(箇条書きの貼り付けテキスト)。`
- 別の傾向として、経緯（日付・指示・旧デザイン）をビューのコメントに積み重ねる書き方が多く、古い記述が残る原因になっています。例: home/index.html.erb:21-23、layouts/application.html.erb:114-117、C-23 の「太字」「アクセント」「印章」。

## 未確認のまま残した範囲

- **ja.yml の未使用キー**: 確認したのは、葉キー名の単語一致検索、動的キーの一覧化、2階層目のキーの照合（admin.words / admin.annotations / home.index / words.show / words.index）だけです。`title` のようにありふれた名前の葉キーはこの方法では検出できません（見逃しうる）。labels.en、stats.index、admin.word_candidates、admin.candidates、pages 配下は個別に確認していません。
- **管理ビューの精読**: 次のファイルは grep で拾っただけで、読み通していません。
  - admin/candidates/*（_bar, _export, _import_form, _review, _row, _stepper, _toolbar, _word, 各段の show）
  - admin/tags/*
  - admin/annotation_decks/_card, _deck（一部だけ読んだ）
  - admin/annotations/_proposal*, _feature_fields, _new_master, _variant_fields
  - admin/bulk_proposal_approvals/show、admin/annotation_proposals/*、admin/word_candidates/*
- **統計・共有パーシャル**: stats/_origins, _sound_breakdown, _sound_matrix, _vowel_graph, _feature_ranking, _entity_cell、shared/_kana_ring_art, _radial_art, _brand_mark、share_cards/word.svg.erb は未精読です。pages/privacy は冒頭だけ読みました。
- **既存テスト**: ほぼ未精読です。本文で「固定済み」と書いた箇所以外は、既存テストでカバーされているかどうかを確認していません。
- **モデル側**: ProposedMasterCreation・TagKind・Genre・annotation_masters の正規化と検証（C-13, C-20 の推測部分）は読んでいません。
- **インフラ**: nginx などの共有キャッシュの有無（C-03 の影響範囲）は確認していません。
- **JS との対応**: Stimulus の data-controller 名と app/javascript の対応は確認していません。
- **ジョブ**: コントローラからの `perform_later`（:async ジョブ）の有無は検索していません。
