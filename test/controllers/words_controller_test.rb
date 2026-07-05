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

  test "一覧の各行に読みの文字数と品詞タグが表示される" do
    get words_path
    assert_response :success
    # 文字数は読みの文字数(さつじんじけん=7字)。
    assert_select ".entry-row__len", text: I18n.t("words.index.char_count", count: word_senses(:murder).reading.length)
    # 品詞タグはファセット絞り込み(単語一覧)への実リンク。
    assert_select "a.entry-row__tag[href=?]", words_path(part_of_speech_id: parts_of_speech(:noun).id),
      text: parts_of_speech(:noun).name
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
    assert_select "p", text: I18n.t("words.index.empty")
  end

  test "検索フォーム由来の配列条件(先頭文字・複数OR)でも絞り込める" do
    get words_path(first_char: [ word_senses(:curry).first_char, word_senses(:murder).first_char ])
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end

  test "一致が無いときは空メッセージを表示する" do
    get words_path(first_char: "ヲ")
    assert_response :success
    assert_select "p", text: I18n.t("words.index.empty")
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

  # --- ページネーション ---
  test "page パラメータで一覧を切り替えられる" do
    get words_path(page: 2)
    assert_response :success
  end

  test "不正な page でも 1 ページ目として扱う" do
    get words_path(page: "-5")
    assert_response :success
  end

  # --- ルーティング(公開は index/show のみ) ---
  test "公開は index/show のみで登録経路は無い" do
    assert_routing "/words", controller: "words", action: "index"
    assert_routing "/words/1", controller: "words", action: "show", id: "1"

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/words", method: :post)
    end
  end
end
