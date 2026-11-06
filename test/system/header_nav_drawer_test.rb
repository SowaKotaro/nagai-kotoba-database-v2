require "application_system_test_case"

# 狭幅(900px 以下)のヘッダーのドロワー(nav-drawer。docs/design.md §5.1)。
# 開閉(ハンバーガーが × になって、そのまま閉じるボタンを兼ねる)とフォーカスの行き来、閉じている間はナビが隠れていること
# (画面の外へ退かせるだけだと Tab で入っていた)、ドロワーのリンクで移ってから戻ったときに開いて見えないこと
# (開いたまま Turbo にキャッシュしない)、「検索」の折り畳みが開閉し、テーマを切り替えても畳まれないことを確かめる。
class HeaderNavDrawerTest < ApplicationSystemTestCase
  # 開閉はトグル(冪等でない)なので click_expecting は使わず素のクリックで検証する。
  test "狭幅のドロワーは、ハンバーガーが × になって開閉し、閉じている間と戻ったときは隠れている" do
    with_window_size(390, 844) do
      visit words_path
      wait_for_stimulus "nav-drawer"
      assert_drawer_closed

      # 閉じている間は、ハンバーガーから Tab で進んでもドロワーの中に入らない(Selenium は画面の外の要素も
      # 「見えない」と数えるので、見えるかどうかでは確かめられない)
      find(".nav-toggle").send_keys(:tab)
      assert_not page.evaluate_script("!!document.activeElement.closest('.site-header__right')"), "閉じたドロワーに Tab で入った"

      # 開いてもフォーカスはハンバーガーに残る(× になったそれが閉じるボタンを兼ねる)。開いている間はドロワーの手前に出ていて、
      # もう一度押せば閉じる。閉じるときは、ドロワーの中にあったフォーカスだけをハンバーガーへ戻す
      open_drawer
      assert_equal "nav-toggle", active_element_class
      assert_selector ".site-nav > a.is-current", text: I18n.t("layouts.nav.words")
      assert_equal "nav-toggle", topmost_class_at_toggle, "開いたドロワーにハンバーガーが隠れた"

      press_key "Escape"
      assert_drawer_closed

      open_drawer
      find(".nav-toggle").click
      assert_drawer_closed

      # 「検索」は、ドロワーの中で折り畳まれていて、押すと配下の行が開く(開いたまま閉じても、次に開いたときは畳まれている)
      open_drawer
      assert_no_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.genres")
      find(".nav-menu__trigger").click
      assert_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.genres")
      find(".nav-menu__trigger").click
      assert_no_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.genres")

      # 開いたままドロワーの中のほかの行(テーマの切り替え)を押しても、畳まれない(畳まれると、ドロワーの高さが変わる)。
      # ダブルタップのズームはアプリ全体で止めている(2 本指のズームは残す)
      find(".nav-menu__trigger").click
      assert_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.genres")
      find(".theme-toggle__button").click
      assert_selector ".theme-toggle__button[aria-checked='true']"
      assert_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.genres")
      assert_selector ".nav-menu__trigger[aria-expanded='true']"
      find(".theme-toggle__button").click # テーマの記憶(localStorage)をほかのテストに残さない
      assert_selector ".theme-toggle__button[aria-checked='false']"
      assert_equal "manipulation", page.evaluate_script("getComputedStyle(document.documentElement).touchAction")

      # 開いたままドロワーを閉じて開き直すと、「検索」は開いたまま残る。開き直したときに順に出る行には、中の行も含めて、上から順に
      # 番号が振られる(中の行だけ先に居るように見えないよう、同じ並びで出す。畳んでいれば数えない)
      find(".nav-toggle").click
      assert_drawer_closed
      open_drawer
      assert_selector ".nav-menu__panel a", text: I18n.t("layouts.nav.genres")
      rows = page.evaluate_script(<<~JS)
        [".nav-menu__trigger", ".nav-menu__panel a:first-child", ".nav-menu__panel a:last-child", ".theme-toggle__button"]
          .map((selector) => Number(document.querySelector(selector).style.getPropertyValue("--row")))
      JS
      assert_equal rows.sort.uniq, rows, "行の番号が上から順になっていない: #{rows}"

      press_key "Escape"
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

  # ハンバーガーの中心の点にいちばん手前で見えている要素(ドロワーとスクリムの手前に出ているか)
  def topmost_class_at_toggle
    page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector(".nav-toggle").getBoundingClientRect()
        const el = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2)
        return el.closest(".nav-toggle") ? "nav-toggle" : el.className
      })()
    JS
  end
end
