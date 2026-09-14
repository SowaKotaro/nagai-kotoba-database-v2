require "application_system_test_case"

# ヘッダーナビの「検索」プルダウン(ジャンル/索引/詳細検索)の開閉と遷移。
class HeaderNavMenuTest < ApplicationSystemTestCase
  # プルダウンの開閉はトグル(冪等でない)なので click_expecting は使わず素のクリックで検証する。
  test "「検索」のプルダウンは Escape やメニューの外側のクリックで閉じ、選んだ先へ遷移する" do
    visit root_path
    wait_for_stimulus("nav-menu")
    assert_no_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.advanced_search")

    open_nav_menu
    find("body").send_keys(:escape)
    assert_nav_menu_closed

    # メニュー外なら何でもよいが、遷移してしまうリンクは避ける(ヒーローの見出しを押す)
    open_nav_menu
    find("h1").click
    assert_nav_menu_closed

    # ジャンル・索引・詳細検索が並び、選んだ先へ遷移する。遷移先ではトリガーが現在地表示になる
    open_nav_menu
    within ".nav-menu__panel" do
      assert_selector "a", text: I18n.t("layouts.nav.genres")
      assert_selector "a", text: I18n.t("layouts.nav.browse")
      click_on I18n.t("layouts.nav.advanced_search")
    end
    assert_current_path search_path
    assert_selector ".nav-menu__trigger.is-current"
  end

  private

  def open_nav_menu
    find(".nav-menu__trigger").click
    assert_selector ".nav-menu__trigger[aria-expanded='true']"
  end

  def assert_nav_menu_closed
    assert_selector ".nav-menu__trigger[aria-expanded='false']"
    assert_no_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.advanced_search")
  end
end
