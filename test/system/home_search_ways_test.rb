require "application_system_test_case"

# ホームの探し方の入口のうち、押すとその場で選択肢が開くボタン(home/_search_way_menu。開閉は nav-menu)。
class HomeSearchWaysTest < ApplicationSystemTestCase
  # 開閉はトグル(冪等でない)なので click_expecting は使わず素のクリックで検証する(HeaderNavMenuTest と同じ)。
  test "開くボタンは押すとその場で選択肢を開き、別のボタンを押すと入れ替わり、選んだ絞り込みの一覧へ進む" do
    literature = genres(:large_literature)
    visit root_path
    wait_for_stimulus("nav-menu", selector: ".search-ways [data-controller~='nav-menu']")

    find(".search-ways__toggle", text: I18n.t("layouts.nav.genres")).click
    assert_selector "#search-way-genre a", text: literature.name

    # 別のボタンを押すと、開いていたほうは閉じる(開くのは常に 1 つ)。Escape でも閉じる
    find(".search-ways__toggle", text: I18n.t("layouts.nav.entity_types")).click
    assert_selector "#search-way-entity-type a", text: entity_types(:book_title).name
    assert_no_selector "#search-way-genre a", text: literature.name
    find("body").send_keys(:escape)
    assert_no_selector "#search-way-entity-type a", text: entity_types(:book_title).name

    find(".search-ways__toggle", text: I18n.t("layouts.nav.genres")).click
    within("#search-way-genre") { click_on literature.name }
    assert_current_path words_path(genre_id: literature.id)
  end
end
