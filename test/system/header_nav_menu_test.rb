require "application_system_test_case"

# ヘッダーナビの「検索」プルダウン(ジャンル/索引/詳細検索)の開閉と遷移。
class HeaderNavMenuTest < ApplicationSystemTestCase
  # プルダウンの開閉はトグル(冪等でない)なので click_expecting は使わず素のクリックで検証する。
  def open_nav_menu
    visit root_path
    wait_for_stimulus("nav-menu")
    assert_no_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.advanced_search")

    find(".nav-menu__trigger").click
    assert_selector ".nav-menu__trigger[aria-expanded='true']"
  end

  test "「検索」をクリックするとジャンル・索引・詳細検索が開き、選んだ先へ遷移する" do
    open_nav_menu

    within ".nav-menu__panel" do
      assert_selector "a", text: I18n.t("layouts.nav.genres")
      assert_selector "a", text: I18n.t("layouts.nav.browse")
      click_on I18n.t("layouts.nav.advanced_search")
    end

    assert_current_path search_path
    # 遷移先ではトリガーが現在地表示になる
    assert_selector ".nav-menu__trigger.is-current"
  end

  test "Escape でプルダウンが閉じる" do
    open_nav_menu

    find("body").send_keys(:escape)
    assert_selector ".nav-menu__trigger[aria-expanded='false']"
    assert_no_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.advanced_search")
  end

  test "メニューの外側をクリックするとプルダウンが閉じる" do
    open_nav_menu

    # メニュー外なら何でもよいが、遷移してしまうリンクは避ける(ヒーローの見出しを押す)
    find("h1").click
    assert_selector ".nav-menu__trigger[aria-expanded='false']"
    assert_no_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.advanced_search")
  end
end
