> 計画書の反証レビュー（P-02。基準コミット e2a8071）。読み取りだけで作業した。

# 計画書の反証レビュー

## 結論（3〜5 行。計画をこのまま進めてよいか、直すべき点の数と重さ）

このままでは進めない方がよい。ただし区分・順序・正典の骨格は作り直さなくてよく、計画書の該当行を直せば進められる。
「出力は同一」としながら公開の出力を変えてしまう項目が 3 件ある（PR-1 今日の一語、PR-2 円環交差数、PR-7 ジャンルの横棒）。既存テストを壊す削除も 1 件ある（PR-3）。
順序と検証の設計にも穴が 4 件ある（PR-4 並列化の単位、PR-5 節番号の参照、PR-6 og:image の安全網、PR-8 robots.txt）。とくに PR-4・PR-5 は、計画の目的（嘘を作らない）に直結する。
残りの 8 件（PR-9〜PR-16）は、計画書の記述を足すか直せば済む。

## 指摘

### [PR-1] C3-18 の `Word.featured_on(date)` は、今日の一語を「キャッシュした語数」ではなく「その場の語数」で選ぶ形になり、公開のホームが変わる
- 対象: §5 C3-18（今日の一語）、T0-04
- 種類: 振る舞いの変更
- 確度: 確認済み（いまの選び方がキャッシュの語数に依存していること）。新しいメソッドが語数を数え直すかどうかは、計画の書き方（引数が `date` だけ）からの推測
- 根拠:
  - `HomeController#index`（app/controllers/home_controller.rb:11-22）は、語数を `Rails.cache.fetch("home/stats/YYYY-MM", expires_in: 1.hour)` に置き、`@word_count = stats[:words]` にする。
  - `HomeController#featured_word`（:48-57）は、その `@word_count` で選ぶ。`return nil if @word_count.zero?`（:49）と `.offset(Date.current.jd % @word_count)`（:55）。
  - 語を公開・保留した直後の最大 1 時間は、キャッシュの語数と実際の語数がずれる。いまの実装は、ずれた数のまま選んでいる。
  - test 環境のキャッシュは `:null_store`（config/environments/test.rb:29）なので、テストの中では両者が常に一致する。T0-04 の「今日の一語」のテストでは差を検出できない。
- 問題:
  - `featured_on(date)` の中で `Word.annotated.count` を数え直すと、公開・保留の直後に別の語が出る（割る数が変わるため）。
  - キャッシュで省いていた COUNT も、毎リクエストに戻る（Issue 26 で消したもの）。
- 直し方の提案:
  - C3-18 を「`Word.featured_on(date, count:)` とし、count にはキャッシュした語数を渡す」と書く。
  - T0-04 に、キャッシュを有効にし、キャッシュの語数と実数が違う状態でも同じ語が選ばれることを確かめるテストを足す。C3-11 の `with_rails_cache` はまだ無いので、テストの中で局所的に差し替える。

### [PR-2] C3-13 で円環交差数を保存列から出す前に、本番で保存列と計算値が一致していることを確かめる手順が無い（群ごとに merge すると C3-12 と同時に本番へ出る）
- 対象: §5 C3-13（と C3-12）、§6 第5群、STRATEGY §5
- 種類: 振る舞いの変更／依存・順序
- 確度: 確認済み（コード）。本番データにずれがあるかは推測（下の理由で、ずれは無い見込み）
- 根拠:
  - いまの詳細ページは、読みから毎回計算している（app/views/words/_kana_ring.html.erb:3 `KanaRing.crossing_count(reading)`）。
  - `KanaRing.crossing_count`（app/models/kana_ring.rb:55-64）は常に整数を返す。そのため、:6-7 の else（「—」）にはいまは到達しない。
  - 保存列 `word_senses.ring_crossing_count` は NULL を許す（db/schema.rb:170）。保存列に切り替えると、else は NULL の行で到達するようになる。else を消すと、NULL の行は「回」だけを出す。
  - 保存列のずれを検出・修復する手段は、いまは無い。`backfill:reading_metrics`（lib/tasks/backfill.rake:7-21）も `backfill:verify`（:31-66）も ring_crossing_count を扱わない（M-01）。C3-12 でやっと verify できるようになる。
  - STRATEGY.md:99 は「merge の区切りは群の切れ目」とする。C3-12 と C3-13 は同じ第5群なので、本番には同じデプロイで出る。本番で verify を流せるのは、そのデプロイの後になる。
  - ずれは無い見込み。その理由は次のとおり。
    - 列は、移行（db/migrate/20260721103000_add_ring_crossing_count_to_word_senses.rb:24-29）で全行を埋めた。以後は `WordSense#assign_reading_derivations`（word_sense.rb:153）が作る。
    - KanaRow は 0bbad24（07-19）以降、KanaRing の計算は d30ca55（07-21）以降、変わっていない。ee7a328 で KanaRing に入ったのは、コメントと stroke_length だけ。
    - reading を update_all で書き換える経路は app に無い。
    - ランキングは、すでに保存列で並べて表示している（word_sense_metrics.rb:41-42）。
- 問題:
  - 本番に 1 行でもずれ（または NULL）があると、詳細ページの「N回」が変わる。
  - 計画は「C3-12 で verify の対象になった後に行う」と書くが、本番で verify を実行する手順が無い。
- 直し方の提案:
  - C3-13 の前提に、次の手順を足す。本番で C3-12 版の `bin/rails backfill:verify` を実行し、ring_crossing_count の不整合が 0 件であることをオーナーに確かめてもらう。
  - そのために、第5群の merge を C3-12 の後で一度切る。STRATEGY §5 の例外として書く。
  - else は消さずに「NULL のとき」として残す。または、`ring_crossing_count` に NOT NULL を足す案を §7.2 に書く。

### [PR-3] R2-01 で消す「2 つの total」は、既存テストが参照している
- 対象: §5 R2-01（統計の使われていない戻り値。A05-9）
- 種類: 前提の誤り
- 確度: 確認済み
- 根拠:
  - `SiteStatistics#build_vowel_spectrum` の `total`（app/models/site_statistics.rb:270、:283）は、test/models/site_statistics_test.rb:114 `assert_equal 2, spectrum[:total]` が見ている。
  - `SiteStatistics#build_feature_ranking` の `total`（:362）は、同 :164 `assert_equal 2, ranking[:total]` が見ている。
  - 補完監査は「テストが参照していないことは確認した」（audits/supplement/A-05.md:234）と書いているが、これは誤り。
  - `stats_timeline_chart` の `price_bottom`（app/helpers/stats_helper.rb:81）と出来高の棒の `count`（:395）は、ビューからもテストからも参照が無い。こちらは確かめた。
- 問題: 消すと既存テストの期待値を変えることになり、§0.2 に反する。
- 直し方の提案:
  - R2-01 から 2 つの total を外し、R2-01 自身の決まり（テストからしか使われていないものは消さずに注記する。D1-12）に回す。
  - 消したいなら §7.3 に回す。

### [PR-4] 第2群の並列化を「ディレクトリ」で分けると、1 項目が複数の担当に割れ、同じファイルを複数の担当が触る。STRATEGY §4 とも食い違う
- 対象: §6「作業の決まり」の並列化（計画書:622-625）、第2群（D1-07〜D1-21）
- 種類: 依存・順序
- 確度: 確認済み（計画書の影響ファイル欄の突き合わせ）
- 根拠:
  - 第2群の多くの項目は、ディレクトリをまたぐ。
    - D1-10 は docs・helpers・models・stylesheets にまたがる。
    - D1-14 は views と config/locales、D1-15 は config と javascript にまたがる。
    - D1-17 は config・lib・docs・test、D1-18 は docs と controllers/concerns にまたがる。
  - 同じファイルを、複数の項目が触る。
    - CLAUDE.md（D1-07・D1-09・D1-21）、docs/design.md（D1-09・D1-21）
    - docs/data-model.md（D1-07・D1-17・D1-18）、docs/overview.md（D1-07・D1-17）
    - docs/stats.md（D1-08・D1-10）、docs/issues.md と changelog.md（D1-07・D1-08）
    - stats_helper.rb（D1-10・D1-14）、site_statistics.rb と morpheme_cloud.rb（D1-10・D1-12）
    - seed_catalog.rb（D1-11・D1-12・D1-19）、components.css（D1-10・D1-16）
    - config/locales/ja.yml（D1-06・D1-14・D1-20）
  - STRATEGY.md:91（§4）は「サブエージェントには、書き込んでよいファイルを 1 つだけ渡す」。ディレクトリ単位の割り当てと合わない。
- 問題:
  - 「1 項目 = 1 コミット以上」と、台帳の 1 行が成り立たない。たとえば D1-10 は 4 担当のコミットに割れ、どれが終われば完了か決まらない。
  - 並列の担当が同じファイルを書き換えると、統合で衝突するか、片方の修正が黙って消える。
- 直し方の提案:
  - 並列化の単位を「項目」にする。影響ファイルが重ならない列に分け、列の中は直列にする。
  - 列の例:
    - 文書の列: D1-07 → D1-08 → D1-17 → D1-18
    - デザインの列: D1-09 → D1-21 → D1-16
    - 統計・モデルの列: D1-10 → D1-12 → D1-13 → D1-14 → D1-15
    - マスタの列: D1-11 は D1-06 → D1-19 → D1-20 の後
  - STRATEGY §4 の「1 ファイル」に合わせる。または STRATEGY 側を「1 項目の影響ファイル」に直す。

### [PR-5] 節番号で文書を指すコメントが多く、D1-10・D1-09・D1-21・G4-01・G4-02 で節を動かすと、参照が黙ってずれる。D1-10 の影響ファイルは、参照元の大半を漏らしている
- 対象: §5 D1-10（stats.md の節を別の記号にする）、D1-09・D1-21（design.md に節を足す）、G4-01（CLAUDE.md のデザインの節を design.md へ移す）、G4-02（経緯を移す）、§4.7
- 種類: 依存・順序
- 確度: 確認済み
- 根拠:
  - `stats.md §N` を書いているのは 10 ファイル。app/views/stats/ の 7 つ（_number_wall・_length_chart・_word_cloud・_timeline_chart・_sound_breakdown・_feature_ranking・_vowel_graph）と、stats_helper.rb、panel_switch_controller.js、components.css。
  - D1-10 の影響ファイル欄にあるのは、stats_helper.rb・site_statistics.rb・morpheme_cloud.rb・components.css だけ。ビュー 7 つと JS が無い。
  - 文書名を付けずに「統計ページ §N」「§N」と書くファイルもある（tokens.css、morpheme_extractor.rb、word_sense.rb、morpheme_cloud.rb、morpheme_frequencies.rb、vowel_graph_controller.js、word_sense_search.rb、lib/tasks/stats.rake など）。
  - `§` を含むファイルは、app・lib・config・test で 51 ある。紙面の章を指すのか文書の節を指すのかは、1 つずつ読み分ける必要がある。
  - `design.md §N` は 27 ファイルが参照している。一方で、design.md の節を動かす項目が 4 つある。
    - D1-09・D1-21 は、design.md に節と表を足す。
    - G4-01 は、CLAUDE.md のデザインの節（約 78 行）を design.md へ移す。
    - G4-02 は、改訂履歴と試作の記録を docs/history へ移す。
  - 節番号を保つ決まりは、計画書のどこにも無い。
- 問題:
  - 計画の目的の 1 番（嘘の情報がない）に反する参照のずれを、計画自身が作る。
  - 担当がディレクトリで分かれると（PR-4）、文書を直す担当は、コード側の参照を直せない。
- 直し方の提案:
  - D1-10 の影響ファイルに、上の 10 ファイルと、§N を書く app・lib のファイルを足す。または「`grep -rn '§[0-9]' app lib config test` の結果をすべて確かめる」を完了条件にする。
  - §4.7 に「design.md・stats.md の既存の節番号は変えない」と書く。足すときは末尾か小節にし、移すときは欠番にして、行き先を 1 行残す。
  - D1-09・D1-21・G4-01・G4-02 の完了条件に、「`design.md §`・`stats.md §` の参照先がすべて実在する」を入れる。

### [PR-6] og:image（共有カードの版）を守る特性テストが無い。版は SVG のバイト列から決まり、C3-16・C3-14・C3-09・C3-15 と、svg.erb を触る D1-14・G4-04 がその入力に触れる
- 対象: §0.2（og:image を変えない）、§5 T0（該当なし）、C3-16・C3-14・C3-09・C3-15・D1-14・G4-04
- 種類: 依存・順序（安全網の欠落）／振る舞いの変更のおそれ
- 確度: 確認済み（仕組み）。実際にずれるかは実装しだいなので推測
- 根拠:
  - 詳細ページの og:image の URL には、版が付く（app/views/words/show.html.erb:8 `v: share_card.digest`）。
  - 版は SVG 全体の SHA256 である（`WordShareCard#digest`、app/models/word_share_card.rb:80-81）。SVG が 1 バイトでも変われば、全語の og:image の URL が変わり、焼き直しが走る（`ShareCardRenderer::RENDER_LOCK` で 1 本ずつ）。
  - SVG の入力は次の 4 つで、それぞれ計画の項目が触る。
    - 代表語義: :61 `min_by(&:id)`（C3-14）
    - 円環の点: :103-104 `KanaRing.path` から `KanaRow.base`・`KanaRow.normalize` へ（kana_row.rb:65-76。C3-09・C3-15）
    - 標識のドメイン: :126-127 `URI.parse(canonical_host).host.upcase`（C3-16）
    - テンプレート: app/views/share_cards/word.svg.erb（D1-14・G4-04）
  - svg.erb の ERB コメント行は出力から消えるが、その間の空行（:12・:22・:33）は出力に入る。コメントを消すついでに空行を詰めると、バイト列が変わる。
  - `config.x.canonical_host` はスキーム付き（config/application.rb:49 `"https://…"`）なのに、名前は host である。裸のホストを使うのは共有カードだけ。C3-16 の `SiteUrl` は「host / absolute(path)」としか書いておらず、どちらの意味の host かが決まっていない。
  - 既存の test/models/word_share_card_test.rb が確かめているのは、テキストと点の数（:5-11）と、同じ入力なら版が同じこと（:21-28）だけ。座標・空白・属性の変化は検出できない。
- 問題: §0.2 で守ると宣言した og:image に、変化を検出する仕組みが無い。
- 直し方の提案:
  - T0 に 1 項目足す。フィクスチャの語（abc_murder など）の `WordShareCard#digest` を、文字列で固定する（改修のあいだだけの特性テストとして）。
  - または、C3-09・C3-14・C3-15・C3-16 と svg.erb を触るコミットの完了条件に、全公開語の digest を前後で比べる一時スクリプトを入れる。
  - C3-16 に、`SiteUrl` が「スキーム付きの起点」と「裸のホスト」を別々のメソッドで持つことを書く。

### [PR-7] C3-01 の「genres/index の横棒を RadialChart の比率から求める（同じ式）」は、浮動小数点の丸めで 1% ずれることがある
- 対象: §5 C3-01（genres/index の横棒）
- 種類: 振る舞いの変更
- 確度: 確認済み（`ruby -e` で計算して再現）
- 根拠:
  - ビュー（app/views/genres/index.html.erb:37 の `bar_width`）は `(20 + (count - count_min) * 80.0 / (count_max - count_min)).round` を計算し、:51 で `style="--w: N%"` に出す。
  - `RadialChart.points`（app/models/radial_chart.rb:33）は `ratio = MIN_RATIO + (value - min) / span * (1 - MIN_RATIO)` を計算する（MIN_RATIO = 0.2）。
  - 2 つの式は数学的には等しい。だが比率から `(ratio * 100).round` で幅を出すと、x.5 の境界で結果が変わる。
    - 例: span = 32、count − min = 15 のとき、ビューは 57.5 → 58、比率からは 57.49999999999999 → 57。
    - span ≤ 400 の全組み合わせのうち、18 通りでずれる。
  - `RadialChart.points` は、項目が 3 つ未満だと空を返す（:26）。points から幅を取る実装にすると、大分類が 1〜2 個のときに幅が出ない。
- 問題:
  - 公開の /genres の HTML（`--w` の値）が、データによって 1 だけ変わる。
  - 開発用 DB の前後比較では当たらないことが多く、気づきにくい。
- 直し方の提案:
  - 「同じ式」を「同じ演算順の式」に直す。RadialChart に百分率を返すメソッドを足すなら、ビューと同じ `20 + d * 80.0 / span` の順で計算して丸める、と書く。
  - 完了条件に、旧式と新式を d・span の範囲で総当たりして一致を確かめるテストを入れる。

### [PR-8] robots.txt の `#` の行はコメントではなく公開出力。G4-04・R2-05 の「コメントの整理」が触ると、公開の robots.txt が変わる
- 対象: §5 G4-04（経緯・Issue 番号を docs/history へ移す）、R2-05（Rails の雛形の英語コメント）、D1-07
- 種類: 振る舞いの変更（のおそれ）
- 確度: 確認済み
- 根拠:
  - app/views/robots/show.text.erb の `#` の行は、ERB のコメントではない本文で、そのまま /robots.txt に出る。
    - :1 は Rails の雛形の英語コメント。
    - :3-14 は経緯（Issue 80、3,186 件など）。
  - test/controllers/robots_controller_test.rb:27-31 の `robots_directives` は、`#` の行を除いて比べる。テスト自身が「撤去の経緯をコメントに残してあり、本文には文字列として現れるため」と書いている。行を消しても書き換えても、テストは通る。
  - CLAUDE.md は、robots など検索エンジンから見える挙動を変えるときに確認を求めている。
- 問題:
  - G4-04 は、app/ 全体の「経緯（日付・Issue 番号・計測値）」を移すとしている。:3-14 はその典型的な対象に見える。
  - R2-05 の「雛形の英語コメント」も、:1 と同じ形をしている。
  - どちらを実行しても、公開出力が変わる。
- 直し方の提案:
  - G4-04・R2-05 に「出力されるコメント（robots/show.text.erb の `#` 行）は対象外」と書く。
  - 経緯を移したいなら、それは出力を変える変更として §7.1 に回す（ERB コメント `<%# %>` に変えても、出力から消える）。

### [PR-9] C3-24: 書き出しのキー "reading" は管理画面の HTML とテストに出ている。段の定義の棚卸し（5 か所）も足りない
- 対象: §5 C3-24、§3 の 9、§4.2
- 種類: 前提の誤り
- 確度: 確認済み
- 根拠:
  - 書き出しのキーは、HTML の name・id になる（app/views/admin/candidates/_export.html.erb:31 `text_area_tag "#{export.step}_export"`）。登録待ちの段では `reading_export` になる。
  - このキーは、既存テストが固定している。
    - test/controllers/admin/candidates/registrations_controller_test.rb:11 が `textarea[name=reading_export]` を固定している。
    - test/models/word_candidate_export_test.rb:13 が `WordCandidateExport.new("reading")` を固定している。
  - A04-7 の 5 か所のほかにも、段と状態の対応がある。
    - `WordCandidateReview::CHOICES`（word_candidate_review.rb:10。キーは :triage・:notation）と `context:`（triages_controller.rb:32-33、notations_controller.rb:25）
    - `apply_decisions(statuses: %w[triage held])`（triages_controller.rb:22）と `%w[notated]`（notations_controller.rb:13）
    - 確定した後の行き先（triages_controller.rb:57 `next_stage_path`、notations_controller.rb:17）
    - `WordCandidate.in_progress`（word_candidate.rb:46）
- 問題:
  - 「別名」の reading を段の名前 ready に揃えると、HTML とテストが変わる。
  - 棚卸しから漏れた定義は、C3-24 の後も別の場所に残る。段を足すときに取り残される。
- 直し方の提案:
  - C3-24 に「定数表は、段ごとの書き出しのキーを列として持つ。登録待ちの "reading" は変えない（HTML の name と既存テストに出るため）」と書く。
  - 棚卸しは「5 か所」と数を書かない（§4.7 の決まり）。上の定義も対象に含めるか、含めない理由を書く。
  - A04-11 の「要確認」は決着した（下の「確かめて問題が無かった前提」）。

### [PR-10] C3-12 は「振る舞いを変えない集約」ではなく、運用タスクの欠陥の修正である（rake が書く値と出力が変わる）。区分と §0.2 の扱いを決める必要がある
- 対象: §5 C3-12、区分 C3 の見出し、§0.2
- 種類: 分類の誤り
- 確度: 確認済み
- 根拠:
  - いまの `backfill:reading_metrics`（lib/tasks/backfill.rake:10-17）と `backfill:verify`（:44-58）は、ring_crossing_count を扱わない。
  - `WordSense.reading_derivations` を 3 か所で使えば、それだけで両タスクが ring_crossing_count を書き、報告するようになる。refresh! と words の代表値の照合も足すので、rake が書く値と出力が変わる。
  - 計画も「ring_crossing_count を壊して検出・修復されることを確かめるテストは、本体と同時に足す」と書く。変更の前に通る特性テストを書けない、つまり振る舞いの変更である。
  - §0.2 の「外部から見える振る舞い」の列挙に rake タスクは無く、変えてよいかが決まっていない。
  - なお、refresh! は words.updated_at を進めない（word_sense_metrics.rb:75）。sitemap・ETag の版は動かないので、この点は安全。
- 直し方の提案:
  - §0.2 に「運用タスク（backfill）の欠陥の修正は、公開の表示を変えない範囲で行う」と例外を明記する。C3-12 のリスク欄と §9 の M-01 にも、その旨を書く。
  - または C3-12 を 2 項目に分ける。純粋な集約（扱う列は今の 4 つのまま）と、ring_crossing_count・refresh!・words の照合を足す修正。

### [PR-11] C3-04: 影響ファイルに lib/tasks/stats.rake が無い。rescue の範囲と、判定をメモする意味が変わりうる
- 対象: §5 C3-04、§4.1（外部コマンドの正典）
- 種類: 依存・順序／振る舞いの変更（のおそれ）
- 確度: stats.rake への依存は確認済み。rescue の件は推測（正典に合わせた場合）
- 根拠:
  - lib/tasks/stats.rake:17-18 は、`MorphemeExtractor.new` のインスタンスメソッド `available?`（app/services/morpheme_extractor.rb:49-54）を呼ぶ。ShareCardRenderer の形（クラスメソッド）にすると、ここが壊れる。
  - stats.rake にはテストが無く、MeCab のあるローカルでしか動かない。§0.3 では壊れても気づけない。
  - 正典 §4.1 は「SystemCallError を捕まえる」とする。しかし `ReadingExtractor#call` は `rescue StandardError`（reading_extractor.rb:42）、`MorphemeExtractor#call` は `Errno::ENOENT, IOError, SystemCallError`（:45）を捕まえている。正典に揃えると、捕まえる例外が狭まる。
  - いまは、判定を呼び出しのたびに行う（`ReadingExtractor.call` が毎回 new する。reading_extractor.rb:27-29、:70-74）。
    - クラスでメモすると、MeCab を入れたり外したりした後に再起動が要るようになる（ShareCardRenderer と同じ。share_card_renderer.rb:24-25）。
    - 判定のしかたも 2 つで違う。`MorphemeExtractor#available?` は終了コードを見ない（:50）が、`ReadingExtractor#mecab_available?` は見る（:73）。
- 直し方の提案:
  - C3-04 の影響ファイルに lib/tasks/stats.rake を足す。
  - 完了条件に、次の確認を入れる。MeCab のある環境で `bin/rails stats:morphemes SURFACES_FILE=…` を前後で流し、db/morpheme_frequencies.json の counts が同じこと（generated_at は除く）。
  - 「rescue の範囲と、判定に終了コードを使うかどうかは変えない」と書く。
  - メモ化で再起動が要るようになることは、overview の外部コマンドの表に書く。

### [PR-12] 正典（§4）が、改修の後も残るコードと食い違う（キャッシュの置き場所・RACE_CONDITION_TTL・JS の直書き）
- 対象: §4.1「集計とキャッシュ」、§4.2「キャッシュ」、§4.3「Ruby の値と文言」、C3-10、§7.1 の M-18
- 種類: 分類の誤り（§4 と §5・§7 の食い違い）
- 確度: 確認済み
- 根拠:
  - §4.2 は「コントローラには HTTP の宣言（expires_in / stale?）だけを書く」とする。
    - しかし改修の後も、4 つのコントローラが Rails.cache を持つ（sitemaps_controller.rb:20-21、llms_controller.rb:23-24、home_controller.rb:11、pages_controller.rb:9）。
    - C3-10 は、キーと TTL を定数にするだけで、置き場所は変えない。
    - §4.2 自身も「全件出力は PublishedWordsDigest の版と TTL を使う」と書き、コントローラでのキャッシュを前提にしている。
  - §4.1 は「版付きの CACHE_KEY・CACHE_TTL・RACE_CONDITION_TTL」とする。
    - `WordRanking`（word_ranking.rb:12-13、:59）は race_condition_ttl を持たない（M-18 は §7.1）。
    - `WordRequestDuplicateCheck.cache_key`（word_request_duplicate_check.rb:55-58）と `PagesController#about`（:9）のキーには、版が無い。
  - §4.3 は「JS に日本語や基準値を直書きしない」とする。しかし feature_range_controller.js:113 の「（単語 未選択）」「（読み 未選択）」を直す項目が無い（C3-19・C3-20 の対象外）。
- 問題:
  - G4-01 で CLAUDE.md に載せる正典に、反例が残る。
  - 次のエージェントは、正典と反例のどちらを手本にするか決められない（評価基準 2 に反する）。
- 直し方の提案:
  - 正典に「既知の例外（直さない理由と §7 の ID）」の欄を作り、上を列挙する。
  - または §4.2 を実態に合わせる。「集計値のキャッシュはモデルに置く。全件出力の本文のキャッシュはコントローラに置く（sitemaps・llms）」。home と pages の 2 件は C3-10 でモデルへ移す（キーと TTL を変えなければ、出力は同じ）。
  - M-18 の race_condition_ttl は、鮮度が最大 1 分延びるだけである。C3-10 に入れるか、§4.1 に例外として書く。

### [PR-13] i18n のキーを消す・移す項目で、参照の取り残しをテストが検出しない（test 環境で raise_on_missing_translations が無効）
- 対象: §5 R2-02、C3-07（コピーの文言を 1 組に）、C3-17、C3-19、C3-20
- 種類: 依存・順序（検証の穴）
- 確度: 確認済み
- 根拠:
  - config/environments/test.rb:57 で、`config.i18n.raise_on_missing_translations = true` はコメントアウトされている。
  - ビューに古いキーが残っても、`translation missing` の span になるだけで、文言を assert していない画面ではテストが失敗しない。
  - 計画の検証は「代表ページの HTML の前後比較」である。フラッシュ・空の状態・エラーの表示は、比較の対象から漏れやすい。
- 直し方の提案:
  - これらの項目の完了条件に、どちらかを足す。
    - ローカルで raise_on_missing_translations を一時的に true にして（コミットしない）、`bin/rails test` と `bin/rails test:system` を通す。
    - 消したキーを app・config・test で grep して、0 件であることを確かめる。
  - CFG-12（この設定を常に有効にする件）は、§7.1 のままでよい。

### [PR-14] Capfile と deploy の設定を触る項目に、Capistrano が読み込めることの確認が無い（main への push がそのまま本番デプロイになる）
- 対象: §5 R2-05（staging.rb の削除・Capfile の glob・deploy.rb の例示）、D1-01（deploy.rb の desc、deploy.yml と database.yml のコメント）、§0.3
- 種類: 依存・順序（検証の穴）
- 確度: 確認済み
- 根拠:
  - .github/workflows/deploy.yml:32-35 は、main への push で `bundle exec cap production deploy` を実行し、CI を待たない（§0.2）。
  - §0.3 の合格判定は、Capfile・config/deploy.rb・config/deploy/*.rb を一度も読み込まない。
  - deploy.yml の YAML の誤りも、CI では検出されない。
- 問題: 書き損じは、次の merge の本番デプロイで初めて表に出る。
- 直し方の提案: これらのファイルを触るコミットの完了条件に、2 つを足す。
  - `bundle exec cap -T`（SSH に接続しない）が通ること。
  - deploy.yml と database.yml を、YAML として読めること。

### [PR-15] 特性テストの一部が T0 の外（C3 の各行）に埋もれていて、台帳の行にならない。R2-04 は、T0-09 より前に tokens.css を触る
- 対象: §5 C3-01・C3-03・C3-08・C3-15・C3-18・C3-19、R2-04、T0-09、§6
- 種類: 依存・順序
- 確度: 確認済み（計画書の記述の突き合わせ）
- 根拠:
  - 「先に必要な特性テスト」に、T0 に無いテストを書いた項目が 6 つある。
    - C3-03: 形が不正な入力
    - C3-08: ページ送りの seed・nofollow
    - C3-15: 半角カナ・合成濁点・ゔ・ゕゖ
    - C3-18: 管理一覧のジャンル絞り込み
    - C3-19: 削除済みの語義を数えないこと
    - C3-01: JAPANESE_ORIGIN_NAME がカタログにあること
  - 台帳には「1 項目 = 1 行」で写す。そのため、これらのテストは行にならない。「特性テストは本体と別のコミットにして、先に入れる」が守られたかも確かめようがない。
  - R2-04 は、`--shadow-soft` を tokens.css の 4 か所（:48・:120・:151・:179）と admin.css:40 から消す。ダークの 2 ブロックが一致しているかを確かめる T0-09 は、その後の第4群にある。
  - R2-04 の検証（代表ページの computed style の前後比較）は、静止状態しか見ない。しかし消す宣言には、hover（components.css:2228-2230、annotate.css:166）、ダークのトークン、767px 以下の規則が含まれる。
- 直し方の提案:
  - 上の特性テストを T0-15 以降として T0 に移す。または、台帳に C3-xx-t の行を立てる。
  - T0-09 を第3群の前に出す。または、R2-04 のトークンの削除を第4群の後に回す。
  - R2-04・C3-21 の computed style の比較に、次の状態を含める: :hover と :focus-visible の強制、ダーク、767px と 560px の幅、管理画面。

### [PR-16] 小さな誤り
- C3-11 の「使われていない admins(:two)」:
  - いまは `Admin.take`（14 ファイル）が、おそらく admins(:two) を返す。フィクスチャの id は two が 298486374、one が 980190962 で、two の方が小さいため。置き換えた後に初めて未使用になる。
  - 「管理系のテスト14ファイル」には、sessions_controller_test.rb と test/models/session_test.rb が入っている。
- C3-19: `data-vowel-graph-label-value`（app/views/stats/_vowel_graph.html.erb:13）の値が、`{from}〜{to}拍目: {rows}`（ja.yml:1262）から `%{from}…` に変わる。公開の /stats の HTML が変わるので、C3-20 と同じく明記する。
- C3-14 の影響ファイルにある words/index は、代表語義ではなく「表示中の全語義のうち、読みが最長のもの」を選んでいる（words/index.html.erb:33 の `max_by`）。primary_sense に置き換えない、と書く。
- R2-07 は「A05-9 の CSS の無いクラス」を消すとする。だが `entity-treemap__cell--normal`（_entity_cell.html.erb:6 の補間）は、§4.4 の規則では「CSS に列挙して残す」側である。
- G4-02 の影響ファイルは「docs/ 配下」だが、docs/ の外にも参照がある。README.md:92・:97 と test/integration/published_words_digest_test.rb:5 が、changelog.md・performance-report.md を参照している。
- §0.2 の「外部から見える振る舞い」に、テキストの公開出力（robots.txt・llms.txt・llms-full.txt・sitemap・Atom）と、HTTP の鮮度判定（ETag・Cache-Control）が入っていない。C3-10・C3-16・C3-17・C3-18 がこれらに触る。
- §4.1 は値オブジェクトを `self.call(input)` に揃えるとするが、C3-15 は `KanaFold.to_katakana` を作る。
- C3-13 は派生値に触れるのに、§6 の推奨 effort が high になっている（STRATEGY §3 では、派生値は max）。
- T0-02 の「MeCab が無いとき」は、C3-04 の後も書き換えずに通る作りを指定しておく。たとえば PATH を空にする（判定をメモした後でも Open3 が ENOENT を投げ、退避の分岐に入る）。
- C3-07（A04-4 のコピー欄の統合）: _export.html.erb の textarea の name（`#{step}_export`）は、3 本のテスト（expansions・notations・registrations の controller テスト）が固定している。パーシャルにしても name を保つ、と書く。

## 確かめて問題が無かった前提（主なもの）

- **C3-04: `ReadingExtractor#normalize` を公開しても安全**。
  - reading_extractor.rb:80-84 は引数だけで決まる純粋関数で、インスタンスの状態を読まない。
  - 呼び出し元は、reading_length.rb:18 と reading_extractor_test.rb:51 の 2 つだけで、どちらも `send` で呼んでいる。公開にしても、どちらも動き続ける。
- **D1-20 の要確認: 取り込みは、`senses` の無い提案を受け付ける**。
  - `AnnotationProposalImport#parse`（annotation_proposal_import.rb:46-53）は、Hash であることと word_id しか見ず、PAYLOAD_KEYS で絞るだけ。
  - 表示・反映では、`AnnotationProposal#senses`（annotation_proposal.rb:90-94）が `legacy_sense_hash` から空の語義を 1 件作る。example.json の word_id 125 は、そのまま取り込める。
  - SKILL.md と schema.json には、「senses を省略してよい条件（立項スコア 1 の削除候補など）」を書く方向が実装と合う。required にするなら、if / then の条件付きにする。
- **C3-02: トップレベルの `reading` は、一度も保存されていない**。
  - Issue 38 の初版（47cfdd6）以来、PAYLOAD_KEYS に入ったことが無い（`git log -L` で確認）。
  - payload を書くのは取り込みだけで、テストもトップレベルの reading を使っていない。`legacy_sense_hash` から消しても、出力は同じ。
  - 注意点: `ReannotationExport::SENSE_KEYS`（reannotation_export.rb:15-16）は reading と linguistic_features を含む。定数を 1 つにするとき、これを PAYLOAD_KEYS に混ぜないこと。混ぜると、保存される payload が変わる。
- **C3-15: かなの畳み込みは、同じ式どうし**。
  - NFKC を掛ける 3 実装は、バイト単位で同じ式（word_request_duplicate_check.rb:63、kana_row.rb:75、site_statistics.rb:387）。
  - RhythmPattern（:112）と MoraCount（:22）も同じ式。
- **C3-17: 区切りと URL は同一。名前は 2 種類ある**。
  - 区切りの " › " は、4 か所でバイト列が同じ（20 e2 80 ba 20。ja.yml:386、llms/full.text.erb:57、tags_helper.rb:21、bulk_proposal_approvals/show.html.erb:31）。
  - ライセンスの URL は 3 か所で同じ。
  - 名前は JSON（_license.json.jbuilder:3 の "CC BY 4.0"）と、About・llms（ja.yml:1319）とで違う。2 つとも残す必要がある。
- **C3-10: 式と TTL の前提は成り立つ**。
  - 「今月の新収録」は、home_controller.rb:19 と site_statistics.rb:119 で同じ式。
  - 本番のキャッシュは :memory_store（config/environments/production.rb:69）で、再起動のたびに空になる。キーを変える影響は、計画の記述どおり軽い。
- **C3-18（PR-1 以外）**:
  - WordSort の "created_desc"（word_sort.rb:25）は、ホームと Atom の `order(annotated_at: :desc, id: :desc)` と同じ並び。
  - annotations_controller で提案を 4 回取得している箇所（:30・:49・:79・:94）は、どれも同じ `find_by(word_id:)`。before_action にしても結果は変わらない。`mark_proposal_applied`（:136）の pending 付きの取得は別物として残す。
- **C3-21: 変数化と統合の前提は成り立つ**。
  - 1040px は layout.css の 4 つの max-width（:14・:483・:530・:587）だけで、メディアクエリには無い。変数にできる。
  - `.section-heading` は、ビューで単独のクラスとしてしか使われていない（2 か所）。
  - `.stats-grid` を使うのは、ホームの `--rows` と管理画面のダッシュボードだけ。
- **C3-06: 2 つの判定は、いまのルートでは一致する**。パスの前方一致（application.html.erb:90、_header.html.erb:71）と、型の判定（admin_helper.rb:8-10）。
- **C3-14: 代表語義の選び方は、実質的に揃っている**。
  - `has_many :word_senses` に order は無い。だが一覧・詳細・ホームはどれも includes（preload）で読み、各語の中では id の昇順に並ぶ。
  - related_words.rb:19、shiritori_words.rb:21、word_share_card.rb:61 は、すでに `min_by(&:id)` を使っている。
  - bulk_annotation.rb:46-47 が扱うのは、単一語義の語だけ。
- **C3-03**: `BulkWordRegistration#research_index`（bulk_word_registration.rb:238）も、Hash でない要素を飛ばしている。`ResearchJson.array_at` と同じ扱いである。空の入力でエラーにしない分岐（:254）だけ保てばよい。
- **C3-08**: 3 つのコントローラのページの計算は、同じ式。
- **C3-05**: WordRequestsController のアクションは、new・create・duplicates の 3 つ（routes.rb:21-23）。
- **C3-12: verify に足しても既存テストは通り、版も動かない**。
  - フィクスチャの ring_crossing_count（3・0・12・3）は、`KanaRing.crossing_count` の値と一致した（`bin/rails runner` で計算）。verify に足しても、backfill_task_test の「不整合はありません」は通る。
  - refresh! は updated_at を進めない（word_sense_metrics.rb:75）。
- **R2-01（2 つの total 以外）: 参照は無い**。ArticlesHelper（空のモジュール）、`MergedEntry#match?` と `#differ?`、`WordCandidate::DECISIONS`（参照はコメントだけ）、`sign_out`、Placed の weight、`Layout#any?`、`MorphemeFrequencies.metadata`、price_bottom、出来高の棒の count。
- **R2-02**: crown・sparkle は、データから渡すアイコン名にも無い（WordRanking の icon、legend_icon、ダッシュボードの section.icon）。
- **R2-04**:
  - 確認済みの 8 セレクタは、補間による組み立て（`icon(name, css)` の第 2 引数を含む）でも参照が無い。
  - `--shadow-soft` を参照しているのは、tokens.css・admin.css・design.md だけ。
  - paint-order の相手になる stroke は無い。
- **R2-07**: A07-2 の 8 件と `sense-attrs__item--wide` は、test・JS・ヘルパ・i18n から参照されていない。
- **C3-24 の要確認（A04-11）**: registrations/show.html.erb:18 の文字列は、`WordCandidateExport#text`（:43-45、with_ids: false）と同じ。出力は同一で、意図の確認だけが残る。
- **C3-01（PR-7 以外）**:
  - BulkWordRegistration の別名の定数を参照するテストは無い。
  - site_statistics の文字種の記号（:106-107）は、CharTypePattern の定数と同じ文字。
  - ホームの RANKING_LIMIT について。ビューは `take(5)` で（home/index.html.erb:198）、並びは id で決定的なので、LIMIT を 5 にしても先頭の 5 件は変わらない。
- **D1-13**: Rails 8.1.3.1 の `find_or_create_by!` は、`find_by` の後に `create_or_find_by!` を呼ぶ（activerecord relation.rb:238-240）。

## 未確認のまま残した範囲

- 本番データは見ていない。PR-2 の ring_crossing_count にずれがあるか、PR-7 の境界に当たる語義数の組があるか、は分からない。
- テスト・system テスト・rake は実行していない。HTML と computed style の前後比較もしていない。
  - 実行したのは次の 2 つだけで、どちらも DB を読み書きしていない。
    - `bin/rails runner` でフィクスチャの読みの円環交差数を計算した。
    - `ruby -e` で横棒の式を総当たりした。
- 「要確認」の項目のうち、次のものは確かめていない。
  - C3-18 の管理一覧のジャンル展開が、公開検索と同じ意味か。
  - R2-04 の要確認の 4 セレクタ。
  - C3-23 の入力手段。
  - C3-01 の RANKING_LIMIT（6 件目以降を使う箇所の網羅）。
- D1 の文書修正（D1-06〜D1-21）の文面が正しいかは、抜き取り以外は照合していない。G4 の中身（CLAUDE.md の再編案、docs/history への移し方）も読んでいない。
- §9 の対応表は、監査記録の見出しの ID がすべて載っていることだけを機械的に確かめた。対応先が妥当かは見ていない。
- .claude/skills の本文と、監査 A-08・A-11 の照合はしていない。

## リーダーの裏取り（e2a8071）

- PR-1 を確認した。`app/controllers/home_controller.rb:11` の 1 時間キャッシュ（`home/stats/<年月>`）から取った `@word_count` を、`featured_word`（`:47-57`）が `Date.current.jd % @word_count` に使っている。モデルのスコープでその場の件数を数える形にすると、キャッシュが切れるまでの間に公開語が増えた場合、選ばれる語が変わる。
- PR-3 を確認した。`test/models/site_statistics_test.rb:114` が `spectrum[:total]`、`:164` が `ranking[:total]` を参照している。補完監査 A-05 の A05-9「テストが参照していないことは確認した」は、この 2 つについては誤り。
- PR-7 を確認した。`app/views/genres/index.html.erb:37` は `(20 + (count - count_min) * 80.0 / (count_max - count_min)).round`。`app/models/radial_chart.rb:33` は `MIN_RATIO + (value.to_f - min) / span * (1 - MIN_RATIO)`。span = 32・差 15 のとき、前者は 57.5 を丸めて 58、後者は 0.575 を 100 倍すると浮動小数点の誤差で 57.4999… になり、丸めて 57。
