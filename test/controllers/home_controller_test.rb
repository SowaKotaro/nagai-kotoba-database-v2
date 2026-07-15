require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "未認証でもトップページを閲覧できる" do
    get root_path
    assert_response :success
  end

  test "トップに最長ランキングと、その一覧(読みが長い順)への導線がある" do
    get root_path
    assert_response :success
    assert_select "h2.section-heading", text: /#{Regexp.escape(I18n.t("home.index.ranking"))}/
    assert_select "a[href=?]", words_path(sort: "length_desc")
    # 公開(注釈済み)の語がランキングに並ぶ
    assert_select "section a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end
end
