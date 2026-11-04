require "application_system_test_case"

# 狭幅(900px 以下)のヘッダーのドロワー(nav-drawer。docs/design.md §5.1)。
# 開閉とフォーカスの行き来、閉じている間はナビが隠れていること(画面の外へ退かせるだけだと Tab で入っていた)、
# ドロワーのリンクで移ってから戻ったときに開いて見えないこと(開いたまま Turbo にキャッシュしない)を確かめる。
class HeaderNavDrawerTest < ApplicationSystemTestCase
  # 開閉はトグル(冪等でない)なので click_expecting は使わず素のクリックで検証する。
  test "狭幅のドロワーは開くと閉じるボタンに、閉じるとハンバーガーにフォーカスが移り、閉じている間と戻ったときは隠れている" do
    with_window_size(390, 844) do
      visit words_path
      wait_for_stimulus "nav-drawer"
      assert_drawer_closed

      # 閉じている間は、ハンバーガーから Tab で進んでもドロワーの中に入らない(Selenium は画面の外の要素も
      # 「見えない」と数えるので、見えるかどうかでは確かめられない)
      find(".nav-toggle").send_keys(:tab)
      assert_not page.evaluate_script("!!document.activeElement.closest('.site-header__right')"), "閉じたドロワーに Tab で入った"

      open_drawer
      assert_equal "nav-drawer__close", active_element_class
      assert_selector ".site-nav > a.is-current", text: I18n.t("layouts.nav.words")

      press_key "Escape"
      assert_drawer_closed
      assert_equal "nav-toggle", active_element_class

      open_drawer
      find(".nav-drawer__close").click
      assert_drawer_closed

      open_drawer
      within(".site-header__right") { click_on I18n.t("layouts.nav.ranking") }
      assert_current_path rankings_path
      go_back
      assert_current_path words_path
      assert_drawer_closed
      assert_not page.evaluate_script("document.body.classList.contains('nav-drawer-open')"), "ページのスクロールが止まったまま"
    end
  end

  private

  def open_drawer
    find(".nav-toggle").click
    assert_selector ".nav-toggle[aria-expanded='true']"
    assert_selector ".site-nav a", text: I18n.t("layouts.nav.ranking")
  end

  def assert_drawer_closed
    assert_selector ".nav-toggle[aria-expanded='false']"
    assert_no_selector ".site-nav a", text: I18n.t("layouts.nav.ranking")
  end

  def active_element_class
    page.evaluate_script("document.activeElement.className")
  end
end
