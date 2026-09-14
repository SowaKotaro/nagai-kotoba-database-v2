require "test_helper"

# ランキングのハブ(/rankings)。各枠の順位の出し方と載せる語は WordRankingTest で見る。
class RankingsControllerTest < ActionDispatch::IntegrationTest
  test "ランキングは誰でも見られ、該当語のある枠だけをタブと同じ数だけ並べる" do
    get rankings_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("rankings.index.title")
    assert_select "meta[name=robots]", count: 0

    # フィクスチャでは拗音・促音と語義数の枠が空になるため、11枠中9枠だけ出る
    expected = WordRanking.all.count { |ranking| ranking.top.any? }
    assert_equal 9, expected
    assert_select "section.rank-board", count: expected
    assert_select ".rank-tab", count: expected
    # 先頭のタブだけが押された状態で、パネルはサーバ側では隠さない(JS 無効でも全部読める)
    assert_select ".rank-tab[aria-pressed=true]", count: 1
    assert_select "[data-panel-switch-target=panel][hidden]", count: 0

    # 各枠の「もっと見る」は同じ並びの単語一覧へ。遷移先は必ず noindex(同じ集合の順列違い)なので nofollow
    assert_select ".rank-board__more[href=?]", words_path(sort: "length_desc")
    assert_select ".rank-board__more[href=?]", words_path(sort: "dakuten_desc")
    assert_select ".rank-board__more[rel=nofollow]", count: expected
  end

  test "行は順位・見出し語・指標値・単位を持ち、上位3位には印が付く" do
    get rankings_path
    assert_select "#rank-length-desc .rank-row", count: 2
    assert_select "#rank-length-desc .rank-row:first-child" do
      assert_select ".rank-row__no.rank-row__no--top", text: "1"
      assert_select "a.rank-row__surface[href=?]", word_path(words(:abc_murder)), text: "ABC殺人事件"
      assert_select ".rank-row__number", text: "7"
      assert_select ".rank-row__unit", text: I18n.t("rankings.boards.length_desc.unit")
    end
  end
end
