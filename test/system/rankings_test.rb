require "application_system_test_case"

class RankingsTest < ApplicationSystemTestCase
  # ランキングは種類が多いので、タブで1つずつ切り替えて見せる(縦に積むとページが長くなる)。
  # サーバは全パネルを描画しておき、JS が繋がった時点で初期表示へ畳む。
  # 「もっと見る」のリンク先は RankingsControllerTest で見る。
  test "ランキングはタブで切り替わり、初期表示は先頭の1つだけ" do
    visit rankings_path
    wait_for_stimulus("panel-switch")

    assert_selector "#rank-length-desc"
    assert_no_selector "#rank-dakuten-desc"

    click_expecting(expect_css: "#rank-dakuten-desc") do
      find(".rank-tab", text: I18n.t("rankings.boards.dakuten_desc.title"))
    end
    assert_no_selector "#rank-length-desc"
    # 押されたタブだけが現在地になる
    assert_selector ".rank-tab[aria-pressed='true']", count: 1
  end
end
