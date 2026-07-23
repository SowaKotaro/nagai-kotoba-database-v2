require "test_helper"

class RankingsControllerTest < ActionDispatch::IntegrationTest
  test "ランキングページは未認証で閲覧できる" do
    get rankings_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("rankings.index.title")
    assert_select "meta[name=robots]", count: 0
  end

  test "該当語のある枠だけを並べ、切替タブも同じ数になる" do
    get rankings_path
    # フィクスチャでは拗音・促音と語義数の枠が空になるため、11枠中9枠だけ出る。
    expected = WordRanking.all.count { |ranking| ranking.top.any? }
    assert_equal 9, expected
    assert_select "section.rank-board", count: expected
    assert_select ".rank-tab", count: expected
    # 先頭のタブだけが押された状態で、パネルはサーバ側では隠さない(JS 無効でも全部読める)
    assert_select ".rank-tab[aria-pressed=true]", count: 1
    assert_select "[data-panel-switch-target=panel][hidden]", count: 0
  end

  test "各枠の「もっと見る」は同じ並びの単語一覧へ渡す" do
    get rankings_path
    assert_select ".rank-board__more[href=?]", words_path(sort: "length_desc")
    assert_select ".rank-board__more[href=?]", words_path(sort: "dakuten_desc")
  end

  test "行は順位・見出し語・指標値を持ち、上位3位は刻印になる" do
    get rankings_path
    assert_select "#rank-length-desc .rank-row", count: 2
    assert_select "#rank-length-desc .rank-row:first-child" do
      assert_select ".rank-row__no.rank-row__no--top", text: "01"
      assert_select "a.rank-row__surface[href=?]", word_path(words(:abc_murder)), text: "ABC殺人事件"
      assert_select ".rank-row__number", text: "7"
      assert_select ".rank-row__unit", text: I18n.t("rankings.boards.length_desc.unit")
    end
  end

  test "公開されていない語は載らない" do
    get rankings_path
    assert_select "a.rank-row__surface", text: "バミューダトライアングル", count: 0
  end
end
