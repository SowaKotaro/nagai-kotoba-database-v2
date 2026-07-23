require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "未認証でもトップページを閲覧できる" do
    get root_path
    assert_response :success
  end

  test "収録統計に今月の新収録数を出す" do
    get root_path
    # フィクスチャの公開語2語はどちらも読込時刻(=今月)に作られる。
    assert_select ".stats-grid__item dt", text: I18n.t("home.index.stats.monthly_new")
    assert_select ".stats-grid__item dd", text: /\A2/
  end

  test "トップに最長ランキングと、ランキングページへの導線がある" do
    get root_path
    assert_response :success
    assert_select "h2.home-column__title", text: /#{Regexp.escape(I18n.t("home.index.ranking"))}/
    # 最長以外の番付も束ねたランキングページへ送る(全順位はその先の「もっと見る」から)
    assert_select "a[href=?]", rankings_path
    # 公開(注釈済み)の語がランキングに並ぶ
    assert_select "a.home-column__item[href=?]", word_path(words(:abc_murder))
  end
end
