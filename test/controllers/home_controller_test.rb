require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "未認証でもトップページを閲覧できる" do
    get root_path
    assert_response :success
  end

  test "トップに最長ランキングと、ランキングページへの導線がある" do
    get root_path
    assert_response :success
    assert_select "h2.section-heading", text: /#{Regexp.escape(I18n.t("home.index.ranking"))}/
    # 最長以外の番付も束ねたランキングページへ送る(全順位はその先の「もっと見る」から)
    assert_select "a[href=?]", rankings_path
    # 公開(注釈済み)の語がランキングに並ぶ
    assert_select "section a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end
end
