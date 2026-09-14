require "test_helper"

# 公開の単語一覧・詳細。絞り込みの条件そのものは WordSenseSearchTest、並び順の組み立ては WordSortTest、
# インデックス方針(robots / canonical)は FacetIndexingTest で押さえ、ここでは画面・リンク・キャッシュを見る。
class WordsControllerTest < ActionDispatch::IntegrationTest
  # --- 一覧 ---
  test "一覧は誰でも見られ、行は見出し語・文字数・エンティティ・ジャンルのパンくずを持つ" do
    get words_path
    assert_response :success

    assert_select "article.entry-row"
    # 見出し語(surface)が詳細へのリンク
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder)), text: words(:abc_murder).surface
    # 文字数は読みの文字数(さつじんじけん=7字)
    assert_select ".entry-row__len", text: I18n.t("words.index.char_count", count: word_senses(:murder).reading.length)
    # エンティティタグはファセット絞り込みへの実リンク。品詞は語の見分けに効かないので一覧には出さない
    assert_select "a.entry-row__tag[href=?]", words_path(entity_type_id: entity_types(:book_title).id),
                  text: entity_types(:book_title).name
    assert_select "a.entry-row__tag[href=?]", words_path(part_of_speech_id: parts_of_speech(:noun).id), count: 0
    # ジャンルは大→中→小のパンくずで、各階層が絞り込みリンク(末端は強調する)
    assert_select ".entry-row__data .genre-path" do
      assert_select "a[href=?]", words_path(genre_id: genres(:large_literature).id), text: "文学"
      assert_select "a[href=?]", words_path(genre_id: genres(:medium_japanese).id), text: "日本文学"
      assert_select "a.genre-path__current[href=?]", words_path(genre_id: genres(:small_novel).id), text: "小説"
    end
    # 未注釈の語は出ない
    assert_select "a.entry-row__surface[href=?]", word_path(words(:pending_haruhi)), count: 0
  end

  test "ファセット条件(単一値・配列)で一覧を絞り込める" do
    murder = words(:abc_murder)
    curry = words(:curry)
    {
      { entity_type_id: entity_types(:book_title).id } => [ murder ],
      { genre_id: genres(:large_literature).id } => [ murder ],
      { word_origin_id: word_origins(:kango).id } => [ murder ],
      { reading_length: word_senses(:curry).reading_length } => [ curry ],
      { first_char: word_senses(:curry).first_char } => [ curry ],
      { first_char: [ word_senses(:curry).first_char, word_senses(:murder).first_char ] } => [ murder, curry ],
      { q: "カレー" } => [ curry ]
    }.each do |params, expected|
      get words_path(params)
      assert_response :success
      [ murder, curry ].each do |word|
        assert_select "a.entry-row__surface[href=?]", word_path(word), { count: expected.include?(word) ? 1 : 0 },
                      "#{params} での #{word.surface} の有無が違う"
      end
    end
  end

  test "キーワードが別表記で当たった行にだけ、一致した別表記を注記する" do
    variant = word_sense_variants(:curry_variant)
    get words_path(q: variant.surface)
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "p.entry-row__match", text: I18n.t("words.index.variant_match", surface: variant.surface)

    # 表層形・読みが直接一致した行には注記を出さない
    get words_path(q: "カレー")
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "p.entry-row__match", count: 0
  end

  test "0件のときは絞り込みの有無で案内を出し分ける" do
    get words_path(first_char: "ヲ")
    assert_select "p.empty-note", text: I18n.t("words.index.empty_filtered")

    Word.update_all(annotated_at: nil) # 公開(注釈済み)を無くす
    get words_path
    assert_select "p.empty-note", text: I18n.t("words.index.empty")
  end

  test "絞り込み中だけ条件チップと変更・解除リンクを出す" do
    get words_path
    assert_select ".active-facet", count: 0

    get words_path(part_of_speech_id: parts_of_speech(:noun).id)
    assert_select ".condition-chip__value", text: parts_of_speech(:noun).name
    assert_select "a.active-facet__edit[href=?]", search_path(part_of_speech_id: parts_of_speech(:noun).id)
    assert_select "a.active-facet__clear[href=?]", words_path
  end

  test "不正な page は1ページ目として扱う" do
    get words_path(page: "-5")
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end

  # --- 正規表現(URL 直打ちでも 500 にしない) ---
  test "不正な正規表現は条件から外し、警告を出す" do
    get words_path(regexp: "(ア")
    assert_response :success
    assert_select ".flash--alert", text: /#{I18n.t('searches.regexp_error.syntax')}/
    # 壊れた式は無視されるので、公開語は変わらず並ぶ
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end

  test "照合が打ち切られる正規表現は空の結果と警告を返す" do
    # MySQL が regexp_time_limit を超えて照合を打ち切ったときの動き。この上限は GLOBAL 変数で
    # テストからは絞れず、フィクスチャの短い読みでは実際に踏ませられないため、DB が返すエラーを差し込む。
    timeout = ->(*) { raise ActiveRecord::StatementInvalid, "Mysql2::Error: Timeout exceeded in regular expression match." }
    stub_method(WordSense, :regexp_matching, timeout) do
      get words_path(regexp: "^(ア+)+$X")
    end
    assert_response :success
    assert_select ".flash--alert", text: /#{I18n.t('searches.regexp_error.runtime')}/
    assert_select "a.entry-row__surface", count: 0
  end

  # --- 並び替え(sort) ---
  # 並び順は一覧本文での見出し語の位置で見る。フィクスチャの読みは カレー(3字) と さつじんじけん(7字)。
  test "既定は収録(公開)が新しい順で、下書きを作った順(created_at)ではない" do
    # 一括登録で先に下書きを作り、あとから注釈を終えた語は created_at が古いまま公開される
    words(:abc_murder).update_columns(created_at: 10.days.ago, annotated_at: 1.hour.ago)
    words(:curry).update_columns(created_at: 1.day.ago, annotated_at: 2.days.ago)

    get words_path
    assert_operator body_position(words(:abc_murder)), :<, body_position(words(:curry))

    # 未知の sort は既定に畳む(SQL に混ぜない)
    get words_path(sort: "evil'); DROP TABLE words; --")
    assert_response :success
    assert_operator body_position(words(:abc_murder)), :<, body_position(words(:curry))
  end

  test "並び替えのキーごとに順序が変わる" do
    murder = words(:abc_murder)
    curry = words(:curry)
    murder.update_column(:annotated_at, 2.days.ago)
    curry.update_column(:annotated_at, 1.day.ago)

    {
      "kana_asc" => [ curry, murder ],            # カ < さ
      "kana_desc" => [ murder, curry ],
      "length_asc" => [ curry, murder ],          # 3字 < 7字
      "length_desc" => [ murder, curry ],
      "dakuten_desc" => [ murder, curry ],        # さつじんじけん は「じ」が2つ、カレー は 0
      "surface_length_desc" => [ murder, curry ], # ABC殺人事件(7字) > カレーライス(6字)。読みの長さとは別軸
      "created_asc" => [ murder, curry ],
      "created_desc" => [ curry, murder ]
    }.each do |key, (first, second)|
      get words_path(sort: key)
      assert_operator body_position(first), :<, body_position(second), "sort=#{key} の順序が違う"
    end
  end

  test "sort=reverse_kana は読みを末尾から見た辞書順になる" do
    # 反転読みは チカ→カチ、アシ→シア。カ < シ なので チカ の語が先に来る。
    early = Word.create!(surface: "逆引きで先", annotated_at: Time.current)
    early.word_senses.create!(reading: "チカ")
    late = Word.create!(surface: "逆引きで後", annotated_at: Time.current)
    late.word_senses.create!(reading: "アシ")

    get words_path(sort: "reverse_kana")
    assert_operator body_position(early), :<, body_position(late)
  end

  test "並び順のセレクタは選べるキーをひとまとめに並べ、ランキング用の並びも一覧で使える" do
    get words_path
    assert_select "select#sort optgroup", count: 0
    assert_select "select#sort option[value=shuffle]", count: 0
    # 表示順は SELECTABLE_KEYS の順(先頭は既定の「登録が新しい順」)
    labels = css_select("select#sort option").map(&:text)
    assert_equal WordSort::SELECTABLE_KEYS.map { |key| I18n.t("words.index.sort.options.#{key}") }, labels

    # ランキングページの「もっと見る」から辿り着く並び(WordSort::RANKING_KEYS)
    WordSort::RANKING_KEYS.each do |key|
      get words_path(sort: key)
      assert_response :success, "sort=#{key} が失敗した"
      assert_select "select#sort option[selected][value=?]", key
    end
  end

  test "並び順フォームは絞り込み条件(配列を含む)を hidden で引き継ぎ、現在の並びを選択済みにする" do
    get words_path(part_of_speech_id: parts_of_speech(:noun).id, sort: "length_desc")
    assert_select ".sort-form input[type=hidden][name=?][value=?]", "part_of_speech_id", parts_of_speech(:noun).id.to_s
    assert_select ".sort-form select#sort option[selected][value=?]", "length_desc"

    get words_path(first_char: [ word_senses(:curry).first_char, word_senses(:murder).first_char ])
    [ word_senses(:curry), word_senses(:murder) ].each do |sense|
      assert_select ".sort-form input[type=hidden][name=?][value=?]", "first_char[]", sense.first_char
    end
  end

  # --- シャッフル ---
  # シードは URL に載せない。載せると描画のたびに未知の URL が生まれ、クローラが無限に辿れてしまう
  # (Issue 80。シードはサーバ側で振る。WordSort)。noindex・nofollow・canonical は FacetIndexingTest で見る。
  test "シャッフルボタンは絞り込み条件を保ち、シード無しの同じ URL を何度でも出す" do
    get words_path
    assert_select ".entry-toolbar__shuffle", text: /#{Regexp.escape(I18n.t("words.index.shuffle"))}/
    href = css_select(".entry-toolbar__shuffle").first["href"]
    assert_match(/sort=shuffle/, href)
    assert_no_match(/seed=/, href)

    get words_path
    assert_equal href, css_select(".entry-toolbar__shuffle").first["href"], "描画のたびに URL が変わるとクローラの無限ループになる"

    get words_path(part_of_speech_id: parts_of_speech(:noun).id)
    filtered_href = css_select(".entry-toolbar__shuffle").first["href"]
    assert_match(/part_of_speech_id=#{parts_of_speech(:noun).id}/, filtered_href)
    assert_no_match(/seed=/, filtered_href)
  end

  # Turbo はキャッシュ済みのスナップショットをまず preview として描いてから、サーバの応答で描き直す。
  # シャッフルは同じ URL でも並びが毎回変わるので、preview を許すと1クリックで2回シャッフルして見える。
  test "シャッフル中の一覧だけ Turbo の preview を止める" do
    get words_path(sort: "shuffle")
    assert_select "meta[name=turbo-cache-control][content=no-preview]", count: 1

    [ words_path, words_path(sort: "kana_asc") ].each do |path|
      get path
      assert_select "meta[name=turbo-cache-control]", count: 0
    end
  end

  # --- 詳細 ---
  test "詳細は誰でも見られ、Accept: */*(curl・クローラ)でも HTML を返す" do
    # request.format.html? が */* で false になり、関連語が nil のままテンプレートが描画されて
    # 500 になる退行を防ぐ(LLM クローラ対策)
    get word_path(words(:abc_murder)), headers: { "Accept" => "*/*" }
    assert_response :success
    assert_select "article.sense-card"
  end

  test "未注釈の語の詳細は 404" do
    get word_path(words(:pending_haruhi))
    assert_response :not_found
  end

  test "詳細に読み(ルビ)・韻・母音パターン・意味・リード文が出る" do
    sense = word_senses(:murder)
    get word_path(sense.word)

    # 読みは表層形へのグループルビ(<ruby><rt>)で表示する
    assert_select "h2.sense-heading rt", text: sense.reading
    assert_select ".sense-heading-meta", text: /#{sense.rhythm_pattern}/
    assert_select ".sense-heading-meta", text: /#{sense.vowel_pattern}/
    assert_match sense.meaning, response.body
    # 読み・文字数・ジャンルを散文化した定義文(Issue 18)。文面の組み立ては WordsHelperTest で見る
    assert_select ".word-flavor .word-flavor__text", text: /「#{sense.word.surface}」は、読み「#{sense.reading}」/
  end

  test "詳細に Web 検索(別タブ)・シェア(X・URL コピー)・ランダムの導線がある" do
    word = words(:abc_murder)
    get word_path(word)

    href = "https://www.google.com/search?q=#{CGI.escape(word.surface)}"
    assert_select "h1.page-title a.page-title__web-search[href=?]", href do |links|
      assert_equal "_blank", links.first["target"]
      assert_includes links.first["rel"], "noopener"
    end

    # X 共有(intent リンク・canonical URL をエンコードして含む)と URL コピー(Stimulus)
    assert_select "a.share__btn[href^=?]", "https://x.com/intent/post"
    assert_select "a.share__btn[href*=?]", "nagai-kotoba-database.jp%2Fwords%2F#{word.id}"
    assert_select "div.share[data-clipboard-text-value=?]", "https://nagai-kotoba-database.jp/words/#{word.id}"
    assert_select "button.share__btn[data-action=?]", "clipboard#copy"

    # ランダム導線は見出し語ストリップに置く
    assert_select ".page-eyebrow a.eyebrow-random[href=?]", random_words_path
  end

  test "詳細の属性は単語一覧の絞り込みリンクになり、特徴は該当部分のルビつきで出る" do
    sense = word_senses(:murder)
    get word_path(sense.word)

    # ジャンル階層はパンくず(大→中→小)
    assert_select ".genre-path a", count: 3
    assert_select ".genre-path a[href=?]", words_path(genre_id: genres(:large_literature).id), text: "文学"
    assert_select ".genre-path a.genre-path__current[href=?]", words_path(genre_id: genres(:small_novel).id), text: "小説"
    # 品詞・語種・文字数・モーラ数・先頭/末尾文字
    assert_select "a.tag[href=?]", words_path(part_of_speech_id: parts_of_speech(:noun).id), text: "名詞"
    assert_select "a.tag[href=?]", words_path(word_origin_id: word_origins(:kango).id)
    assert_select "a.tag[href=?]", words_path(reading_length: sense.reading_length)
    assert_select "a.tag[href=?]", words_path(mora_count: sense.mora_count)
    assert_select "a.tag[href=?]", words_path(first_char: sense.first_char)
    assert_select "a.tag[href=?]", words_path(last_char: sense.last_char)
    # 言語学的特徴(murder は 連濁:殺人 と 重箱読み:事件)
    assert_select "a.chip[href=?]", words_path(linguistic_feature_id: linguistic_features(:rendaku).id), text: "連濁"
    assert_select "ruby.annotation-target", text: /殺人/
    assert_select "ruby.annotation-target rt", text: "さつじん"
  end

  test "詳細は未登録の属性を「—」で示す" do
    # curry は ジャンル・エンティティ・言語学的特徴が未登録(語種 英語 はあり)
    get word_path(words(:curry))

    assert_response :success
    assert_select ".sense-undefined", text: I18n.t("words.show.undefined"), minimum: 1
    # 登録済みの語種(英語)は「—」にならず、値が出る
    assert_select ".sense-attrs__item", text: /語種.*英語/m
  end

  test "詳細に同じジャンルの関連語が並び、「ん」で終わる語のしりとりは行き止まりになる" do
    # abc_murder(ジャンル 小説)と同じ小分類の別語を用意する
    sibling = Word.create!(surface: "同ジャンルの別語", annotated_at: Time.current)
    sibling.word_senses.create!(reading: "ドウジャンルノベツゴ", genre: genres(:small_novel))

    get word_path(words(:abc_murder)) # 読み さつじんじけん
    assert_response :success
    assert_select "section.related .related__title", text: I18n.t("words.show.related.title")
    # 同ジャンルの別語への実リンク(単語→単語の内部リンク)と、ファセット一覧への「もっと見る」
    assert_select "section.related a.entry-row__surface[href=?]", word_path(sibling)
    assert_select "section.related a.related__more[href=?]", words_path(genre_id: genres(:small_novel).id)

    assert_select "section.related--shiritori .empty-note", text: /しりとりはここで終わり/
    assert_select "section.related--shiritori .entry-list", false
  end

  test "しりとりの次の一手は末尾文字から始まる公開語へ繋がる" do
    # curry(読み カレー → 末尾文字 レ)から「レ」で始まる公開語へ繋ぐ
    next_word = Word.create!(surface: "レンタルビデオ店の閉店", annotated_at: Time.current)
    next_word.word_senses.create!(reading: "レンタルビデオテンノヘイテン")

    get word_path(words(:curry))
    assert_response :success
    assert_select "section.related--shiritori .related__title", text: I18n.t("words.show.shiritori.title")
    assert_select "section.related--shiritori .shiritori__char", text: "レ"
    assert_select "section.related--shiritori a.entry-row__surface[href=?]", word_path(next_word)
    assert_select "section.related--shiritori a.related__more[href=?]", words_path(first_char: "レ")
  end

  # --- HTTP キャッシュ(Issue 26) ---
  test "詳細は ETag を返し、変わっていなければ 304 になる" do
    get word_path(words(:abc_murder))
    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get word_path(words(:abc_murder)), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "マスタ名(ジャンル・祖先のジャンル・品詞)を変えると ETag が変わり、新しい名前が返る" do
    word = words(:abc_murder)
    genre = word_senses(:murder).genre
    {
      genre => "原始仏教",
      genre.parent => "近現代文学",
      parts_of_speech(:noun) => "名詞(改)"
    }.each do |master, new_name|
      get word_path(word)
      etag = response.headers["ETag"]

      master.update!(name: new_name)

      get word_path(word), headers: { "If-None-Match" => etag }
      assert_response :success, "#{master.class} の改名で ETag が変わっていない"
      assert_includes response.body, new_name
    end
  end

  # --- ランダムに1語・ルーティング ---
  test "random は公開(注釈済み)の語の詳細へ飛ばし、公開語が無ければ一覧へ戻す" do
    get random_words_path
    assert_response :redirect
    id = response.location[%r{/words/(\d+)\z}, 1]
    assert id, "詳細へのリダイレクトではない: #{response.location}"
    assert Word.annotated.exists?(id.to_i), "リダイレクト先は公開(注釈済み)の語であること"

    Word.update_all(annotated_at: nil)
    get random_words_path
    assert_redirected_to words_path
  end

  test "公開は index/show/random のみで登録経路は無い" do
    assert_routing "/words", controller: "words", action: "index"
    assert_routing "/words/1", controller: "words", action: "show", id: "1"
    assert_routing "/words/random", controller: "words", action: "random"

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/words", method: :post)
    end
  end

  private

  # 一覧本文中で語の詳細リンクが現れる位置。行ごとに1回しか出ないため、
  # 位置の大小比較で並び順を検証できる。
  def body_position(word)
    position = response.body.index(%(href="#{word_path(word)}"))
    assert position, "#{word.surface} が一覧に見当たりません"
    position
  end
end
