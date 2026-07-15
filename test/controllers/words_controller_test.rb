require "test_helper"

class WordsControllerTest < ActionDispatch::IntegrationTest
  # --- 公開: 未認証で閲覧できる ---
  test "一覧は未認証で閲覧できる" do
    get words_path
    assert_response :success
    # 行の見出し語(surface)が詳細へのリンク。
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder)), text: words(:abc_murder).surface
  end

  test "詳細は未認証で閲覧できる" do
    get word_path(words(:abc_murder))
    assert_response :success
  end

  test "詳細は Accept: */* (curl・クローラ)でも HTML を返せる" do
    # request.format.html? が */* で false になり関連語が nil のまま
    # テンプレートが描画されて 500 になる退行を防ぐ(LLM クローラ対策)
    get word_path(words(:abc_murder)), headers: { "Accept" => "*/*" }
    assert_response :success
    assert_select "article.sense-card"
  end

  test "一覧の行と詳細の語義カードは article でマークアップされる(SEO/LLMO)" do
    get words_path
    assert_select "article.entry-row"

    get word_path(words(:abc_murder))
    assert_select "article.sense-card"
  end

  test "一覧の各行に読みの文字数と品詞タグが表示される" do
    get words_path
    assert_response :success
    # 文字数は読みの文字数(さつじんじけん=7字)。
    assert_select ".entry-row__len", text: I18n.t("words.index.char_count", count: word_senses(:murder).reading.length)
    # 品詞タグはファセット絞り込み(単語一覧)への実リンク。
    assert_select "a.entry-row__tag[href=?]", words_path(part_of_speech_id: parts_of_speech(:noun).id),
      text: parts_of_speech(:noun).name
  end

  test "詳細は ETag を返し If-None-Match で 304 になる(Issue 26)" do
    get word_path(words(:abc_murder))
    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get word_path(words(:abc_murder)), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "詳細の見出しに Web 検索への外部リンク(別タブ)がある" do
    word = words(:abc_murder)
    get word_path(word)

    href = "https://www.google.com/search?q=#{CGI.escape(word.surface)}"
    assert_select "h1.page-title a.page-title__web-search[href=?]", href do |links|
      assert_equal "_blank", links.first["target"]
      assert_includes links.first["rel"], "noopener"
    end
  end

  test "ジャンル名を変えると詳細の ETag も変わり、新しい名前が返る" do
    genre = word_senses(:murder).genre
    assert genre, "この検証には語義にジャンルが必要"

    get word_path(words(:abc_murder))
    etag = response.headers["ETag"]
    assert_select ".genre-path", text: /#{Regexp.escape(genre.name)}/

    genre.update!(name: "原始仏教")

    get word_path(words(:abc_murder)), headers: { "If-None-Match" => etag }
    assert_response :success
    assert_select ".genre-path", text: /原始仏教/
  end

  test "上位ジャンル(祖先)の名前を変えても詳細のパンくずに反映される" do
    parent = word_senses(:murder).genre.parent
    assert parent, "この検証には親ジャンルが必要"

    get word_path(words(:abc_murder))
    etag = response.headers["ETag"]

    parent.update!(name: "近現代文学")

    get word_path(words(:abc_murder)), headers: { "If-None-Match" => etag }
    assert_response :success
    assert_select ".genre-path", text: /近現代文学/
  end

  test "品詞名を変えても詳細に反映される" do
    get word_path(words(:abc_murder))
    etag = response.headers["ETag"]

    parts_of_speech(:noun).update!(name: "名詞(改)")

    get word_path(words(:abc_murder)), headers: { "If-None-Match" => etag }
    assert_response :success
    assert_select "a.tag", text: "名詞(改)"
  end

  # --- 公開: 未注釈は出さない ---
  test "未注釈の語は一覧に出ない" do
    get words_path
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:pending_haruhi)), count: 0
  end

  test "未注釈の語の詳細は 404" do
    get word_path(words(:pending_haruhi))
    assert_response :not_found
  end

  # --- 詳細の表示内容 ---
  test "詳細に語義の読み・韻・意味が表示される" do
    sense = word_senses(:murder)
    get word_path(sense.word)

    assert_response :success
    # 読みは表層形へのグループルビ(<ruby><rt>)で表示する
    assert_select "h2.sense-heading rt", text: sense.reading
    assert_match sense.rhythm_pattern, response.body
    assert_match sense.meaning, response.body
  end

  test "詳細の見出し語ブロックに自己完結の定義文(リード文)が表示される" do
    sense = word_senses(:murder)
    get word_path(sense.word)

    assert_response :success
    # 読み・文字数・ジャンルを散文化した定義文(Issue 18)。「説明」パネルに収めて表示する
    assert_select ".word-flavor .word-flavor__text",
      text: "「ABC殺人事件」は、読み「さつじんじけん」（7文字・7モーラ）の日本語の長い言葉。" \
            "ジャンルは 文学 › 日本文学 › 小説。人を殺す事件"
  end

  test "詳細は未登録の属性を「—」として表示する" do
    # curry は ジャンル・エンティティ・言語学的特徴・別表記が未登録(語種 英語 はあり)。
    curry = word_senses(:curry)
    get word_path(curry.word)

    assert_response :success
    # 未登録の属性は「—」(データ無し)を示す
    assert_select ".sense-undefined", text: I18n.t("words.show.undefined"), minimum: 1
    # 登録済みの語種(英語)は「—」にならず、値が出る
    assert_select ".sense-attrs__item", text: /語種.*英語/m
  end

  test "詳細にシェア導線(X共有・URLコピー)がある" do
    word = words(:abc_murder)
    canonical = "https://nagai-kotoba-database.jp/words/#{word.id}"
    get word_path(word)

    # X 共有(intent リンク・canonical URL をエンコードして含む)
    assert_select "a.share__btn[href^=?]", "https://x.com/intent/post"
    assert_select "a.share__btn[href*=?]", "nagai-kotoba-database.jp%2Fwords%2F#{word.id}"
    # URL コピー(Stimulus)
    assert_select "div.share[data-clipboard-text-value=?]", canonical
    assert_select "button.share__btn[data-action=?]", "clipboard#copy"
  end

  test "詳細に関連語セクションが表示され単語間リンクになる" do
    # abc_murder(ジャンル 小説)と同じ小分類の別語を用意する
    sibling = Word.create!(surface: "同ジャンルの別語", annotated_at: Time.current)
    sibling.word_senses.create!(reading: "ドウジャンルノベツゴ", genre: genres(:small_novel))

    get word_path(words(:abc_murder))
    assert_response :success
    assert_select "section.related .related__title", text: I18n.t("words.show.related.title")
    # 同ジャンルグループに別語への実リンクがある(単語→単語の内部リンク)
    assert_select "section.related a.entry-row__surface[href=?]", word_path(sibling)
    # 「もっと見る」はファセット一覧へ
    assert_select "section.related a.related__more[href=?]", words_path(genre_id: genres(:small_novel).id)
  end

  test "詳細のジャンル階層は単語一覧の絞り込みリンク付きパンくずで表示される" do
    get word_path(word_senses(:murder).word)

    assert_select ".genre-path a", count: 3
    assert_select ".genre-path a[href=?]", words_path(genre_id: genres(:large_literature).id), text: "文学"
    assert_select ".genre-path a.genre-path__current[href=?]", words_path(genre_id: genres(:small_novel).id), text: "小説"
  end

  test "詳細の品詞・エンティティタイプ・特徴は単語一覧への絞り込みリンクになっている" do
    get word_path(word_senses(:murder).word)

    assert_select "a.tag[href=?]", words_path(part_of_speech_id: parts_of_speech(:noun).id), text: "名詞"
    assert_select "a.chip[href=?]", words_path(linguistic_feature_id: linguistic_features(:rendaku).id), text: "連濁"
  end

  test "詳細に韻・母音パターンが見出し語の近くに表示される" do
    get word_path(word_senses(:murder).word)

    assert_select ".sense-heading-meta", text: /#{word_senses(:murder).rhythm_pattern}/
    assert_select ".sense-heading-meta", text: /#{word_senses(:murder).vowel_pattern}/
  end

  test "詳細の拡張データ(語種・文字数・モーラ数・先頭/末尾)は単語一覧の絞り込みリンク" do
    sense = word_senses(:murder)
    get word_path(sense.word)

    assert_select "a.tag[href=?]", words_path(word_origin_id: word_origins(:kango).id)
    assert_select "a.tag[href=?]", words_path(reading_length: sense.reading_length)
    assert_select "a.tag[href=?]", words_path(mora_count: sense.mora_count)
    assert_select "a.tag[href=?]", words_path(first_char: sense.first_char)
    assert_select "a.tag[href=?]", words_path(last_char: sense.last_char)
  end

  test "詳細に言語学的特徴が該当部分つきで表示される" do
    get word_path(word_senses(:murder).word)

    # murder には 連濁:殺人(さつじん) と 重箱読み:事件(じけん) がある。
    assert_match linguistic_features(:rendaku).name, response.body
    assert_match "殺人", response.body
    assert_match "さつじん", response.body
  end

  # --- ファセット絞り込み(単語一覧として結果を出す) ---
  test "エンティティ種別で単語一覧を絞り込める" do
    get words_path(entity_type_id: entity_types(:book_title).id)
    assert_response :success
    # abc_murder は書籍名、curry は種別なし。
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry)), count: 0
  end

  test "ジャンル(大分類)で単語一覧を絞り込める" do
    get words_path(genre_id: genres(:large_literature).id)
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end

  test "語種で単語一覧を絞り込める" do
    get words_path(word_origin_id: word_origins(:kango).id)
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry)), count: 0
  end

  test "読みの文字数で単語一覧を絞り込める" do
    get words_path(reading_length: word_senses(:curry).reading_length)
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder)), count: 0
  end

  test "先頭文字で単語一覧を絞り込める" do
    get words_path(first_char: word_senses(:curry).first_char)
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder)), count: 0
  end

  test "キーワード(q)で単語一覧を絞り込める" do
    get words_path(q: "カレー")
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder)), count: 0
  end

  test "キーワード検索でも未注釈語は出ない" do
    get words_path(q: "涼宮ハルヒ")
    assert_response :success
    assert_select ".entry-row__surface", text: words(:pending_haruhi).surface, count: 0
    # 絞り込み(q)の結果が 0 件 → 絞り込み用の空メッセージ
    assert_select "p", text: I18n.t("words.index.empty_filtered")
  end

  test "検索フォーム由来の配列条件(先頭文字・複数OR)でも絞り込める" do
    get words_path(first_char: [ word_senses(:curry).first_char, word_senses(:murder).first_char ])
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end

  test "絞り込みで一致が無いときは絞り込み用の空メッセージを表示する" do
    get words_path(first_char: "ヲ")
    assert_response :success
    assert_select "p.empty-note", text: I18n.t("words.index.empty_filtered")
  end

  test "絞り込みが無く0件のときは通常の空メッセージ(DBが空)を表示する" do
    Word.update_all(annotated_at: nil) # 公開(注釈済み)を無くす
    get words_path
    assert_response :success
    assert_select "p.empty-note", text: I18n.t("words.index.empty")
  end

  test "絞り込み中は条件チップと変更・解除リンクを表示する" do
    get words_path(part_of_speech_id: parts_of_speech(:noun).id)
    assert_response :success
    assert_select ".condition-chip__value", text: parts_of_speech(:noun).name
    assert_select "a.active-facet__edit[href=?]",
                  search_path(part_of_speech_id: parts_of_speech(:noun).id)
    assert_select "a.active-facet__clear[href=?]", words_path
  end

  test "絞り込みが無いときはインジケータを出さない" do
    get words_path
    assert_select ".active-facet", count: 0
  end

  # --- 並び替え(sort) ---
  # フィクスチャの読みは カレー(3字) と さつじんじけん(7字)。辞書順では カ < さ。
  test "一覧の既定は登録が新しい順" do
    words(:abc_murder).update_column(:created_at, 2.days.ago)
    words(:curry).update_column(:created_at, 1.day.ago)

    get words_path
    assert_response :success
    assert_operator body_position(words(:curry)), :<, body_position(words(:abc_murder))
  end

  test "sort=kana_asc で読みの辞書順になる" do
    get words_path(sort: "kana_asc")
    assert_operator body_position(words(:curry)), :<, body_position(words(:abc_murder))
  end

  test "sort=kana_desc で辞書の逆順になる" do
    get words_path(sort: "kana_desc")
    assert_operator body_position(words(:abc_murder)), :<, body_position(words(:curry))
  end

  test "sort=length_asc で読みが短い順になる" do
    get words_path(sort: "length_asc")
    assert_operator body_position(words(:curry)), :<, body_position(words(:abc_murder))
  end

  test "sort=length_desc で読みが長い順になる" do
    get words_path(sort: "length_desc")
    assert_operator body_position(words(:abc_murder)), :<, body_position(words(:curry))
  end

  test "sort=created_asc / created_desc で登録日時順になる" do
    words(:abc_murder).update_column(:created_at, 2.days.ago)
    words(:curry).update_column(:created_at, 1.day.ago)

    get words_path(sort: "created_asc")
    assert_operator body_position(words(:abc_murder)), :<, body_position(words(:curry))

    get words_path(sort: "created_desc")
    assert_operator body_position(words(:curry)), :<, body_position(words(:abc_murder))
  end

  test "sort=reverse_kana で読みを末尾から見た辞書順になる" do
    # 反転読みは チカ→カチ、アシ→シア。カ < シ なので チカ の語が先に来る。
    early = Word.create!(surface: "逆引きで先", annotated_at: Time.current)
    early.word_senses.create!(reading: "チカ")
    late = Word.create!(surface: "逆引きで後", annotated_at: Time.current)
    late.word_senses.create!(reading: "アシ")

    get words_path(sort: "reverse_kana")
    assert_operator body_position(early), :<, body_position(late)
  end

  test "sort=shuffle は同じ日のうちは順序が安定している" do
    get words_path(sort: "shuffle")
    assert_response :success
    first_order = body_position(words(:curry)) < body_position(words(:abc_murder))

    get words_path(sort: "shuffle")
    assert_equal first_order, body_position(words(:curry)) < body_position(words(:abc_murder))
  end

  test "未知の sort は既定(登録が新しい順)に畳む" do
    words(:abc_murder).update_column(:created_at, 2.days.ago)
    words(:curry).update_column(:created_at, 1.day.ago)

    get words_path(sort: "evil'); DROP TABLE words; --")
    assert_response :success
    assert_operator body_position(words(:curry)), :<, body_position(words(:abc_murder))
  end

  test "既定以外の sort は noindex になり、既定の sort 指定は indexable のまま" do
    get words_path(sort: "length_desc")
    assert_select "meta[name=robots][content=?]", "noindex,follow"

    get words_path(sort: "created_desc")
    assert_select "meta[name=robots]", count: 0
  end

  test "並び順フォームは絞り込み条件を hidden で引き継ぎ、現在の並びを選択済みにする" do
    get words_path(part_of_speech_id: parts_of_speech(:noun).id, sort: "length_desc")
    assert_select ".sort-form input[type=hidden][name=?][value=?]",
                  "part_of_speech_id", parts_of_speech(:noun).id.to_s
    assert_select ".sort-form select#sort option[selected][value=?]", "length_desc"
  end

  test "並び順フォームは配列の絞り込み条件も hidden で引き継ぐ" do
    get words_path(first_char: [ word_senses(:curry).first_char, word_senses(:murder).first_char ])
    assert_select ".sort-form input[type=hidden][name=?][value=?]",
                  "first_char[]", word_senses(:curry).first_char
    assert_select ".sort-form input[type=hidden][name=?][value=?]",
                  "first_char[]", word_senses(:murder).first_char
  end

  # --- ページネーション ---
  test "page パラメータで一覧を切り替えられる" do
    get words_path(page: 2)
    assert_response :success
  end

  test "不正な page でも 1 ページ目として扱う" do
    get words_path(page: "-5")
    assert_response :success
  end

  # --- ランダムに1語 ---
  test "random は公開(注釈済み)の語の詳細へリダイレクトする" do
    get random_words_path
    assert_response :redirect
    assert_match %r{/words/\d+\z}, response.location
    id = response.location[%r{/words/(\d+)\z}, 1].to_i
    assert Word.annotated.exists?(id), "リダイレクト先は公開(注釈済み)の語であること"
  end

  test "公開語が無いとき random は一覧へフォールバックする" do
    Word.update_all(annotated_at: nil)
    get random_words_path
    assert_redirected_to words_path
  end

  test "random は未認証でも使える" do
    get random_words_path
    assert_response :redirect # 302(ログイン画面ではない)
    assert_no_match(/session/, response.location)
  end

  # --- ルーティング(公開は index/show/random のみ) ---
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
