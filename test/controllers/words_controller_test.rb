require "test_helper"

class WordsControllerTest < ActionDispatch::IntegrationTest
  # --- 公開: 未認証で閲覧できる ---
  test "一覧は未認証で閲覧できる" do
    get words_path
    assert_response :success
    assert_select "a", text: words(:abc_murder).surface
  end

  test "詳細は未認証で閲覧できる" do
    get word_path(words(:abc_murder))
    assert_response :success
  end

  # --- 詳細の表示内容 ---
  test "詳細に語義の読み・韻・意味が表示される" do
    sense = word_senses(:murder)
    get word_path(sense.word)

    assert_response :success
    assert_select "h2", text: sense.reading
    assert_match sense.rhythm_pattern, response.body
    assert_match sense.meaning, response.body
  end

  test "詳細にジャンル階層が大 > 中 > 小で表示される" do
    get word_path(word_senses(:murder).word)
    assert_select "dd", text: "文学 > 日本文学 > 小説"
  end

  test "詳細に言語学的特徴が該当部分つきで表示される" do
    get word_path(word_senses(:murder).word)

    # murder には 連濁:殺人(さつじん) と 重箱読み:事件(じけん) がある。
    assert_match linguistic_features(:rendaku).name, response.body
    assert_match "殺人", response.body
    assert_match "さつじん", response.body
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
