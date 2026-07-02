require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  test "検索ページは未認証で開ける" do
    get search_path
    assert_response :success
  end

  test "条件で絞り込んだ結果が表示される" do
    get search_path, params: { first_char: "さ" }
    assert_response :success
    assert_select "td", text: words(:abc_murder).surface
    assert_select "td", text: words(:curry).surface, count: 0
  end

  test "一致が無いときはメッセージを表示する" do
    get search_path, params: { first_char: "ん" }
    assert_response :success
    assert_select "p", text: I18n.t("searches.empty")
  end

  test "ジャンル階層(大)で絞り込める" do
    get search_path, params: { genre_id: genres(:large_literature).id }
    assert_response :success
    assert_select "td", text: words(:abc_murder).surface
  end

  test "page パラメータを付けても開ける" do
    get search_path, params: { page: 2 }
    assert_response :success
  end
end
