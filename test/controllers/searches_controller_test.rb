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

  test "キーワード(q)で絞り込める(ヘッダー検索・ホーム検索の入口)" do
    get search_path, params: { q: "カレー" }
    assert_response :success
    assert_select "td", text: words(:curry).surface
    assert_select "td", text: words(:abc_murder).surface, count: 0
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

  # --- 簡素検索(キーワードのみ・単語単位) ---
  test "簡素検索は未認証で開ける" do
    get simple_search_path
    assert_response :success
  end

  test "キーワード未入力なら入力を促す" do
    get simple_search_path
    assert_select "p", text: I18n.t("searches.simple.prompt")
  end

  test "簡素検索は表層形の部分一致で単語を返す" do
    get simple_search_path, params: { q: "殺人" }
    assert_response :success
    assert_select ".entry-row__surface", text: words(:abc_murder).surface
    assert_select ".entry-row__surface", text: words(:curry).surface, count: 0
  end

  test "簡素検索は読みの部分一致でも返す" do
    get simple_search_path, params: { q: "カレー" }
    assert_select ".entry-row__surface", text: words(:curry).surface
  end

  test "簡素検索は未注釈語を返さない" do
    get simple_search_path, params: { q: "涼宮ハルヒ" }
    assert_response :success
    assert_select ".entry-row__surface", text: words(:pending_haruhi).surface, count: 0
    assert_select "p", text: I18n.t("searches.simple.empty", q: "涼宮ハルヒ")
  end

  test "簡素検索から詳細検索への導線がある" do
    get simple_search_path, params: { q: "殺人" }
    assert_select "a.search-switch, .search-switch a", text: I18n.t("searches.simple.to_advanced")
  end
end
