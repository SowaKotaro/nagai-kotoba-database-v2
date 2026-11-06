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

  # 実際の指の操作は送れないので、touchstart・touchmove・touchend を、touches だけを持つイベントで時間を置いて送る
  # (swipe-dismiss が読むのは touches の clientY と、イベントの時刻だけ)。
  test "狭幅の探し方のシートは、下へのスワイプで閉じる(足りなければ戻り、中身がスクロールされているときは引き下げない)" do
    with_window_size(390, 560) do
      visit root_path
      wait_for_stimulus("swipe-dismiss", selector: ".search-ways__panel")
      find(".search-ways__toggle", text: I18n.t("layouts.nav.genres")).click
      assert_selector "#search-way-genre a", text: genres(:large_literature).name
      # 中身がスクロールできる高さにする(フィクスチャの選択肢は少ない)
      page.execute_script("document.querySelector('#search-way-genre .search-ways__options').style.minHeight = '900px'")

      # 距離が足りないなら、離すと元の位置へ戻る(閉じない)
      swipe_down("#search-way-genre", 50, duration: 800)
      assert_selector "#search-way-genre a", text: genres(:large_literature).name
      assert_equal "", page.evaluate_script("document.querySelector('#search-way-genre').style.translate")

      # 中身が上へスクロールされているときは、ふつうのスクロールを優先する(引き下げない)
      page.execute_script("document.querySelector('#search-way-genre').scrollTop = 80")
      assert_operator page.evaluate_script("document.querySelector('#search-way-genre').scrollTop"), :>, 0
      swipe_down("#search-way-genre", 220, duration: 400)
      assert_selector "#search-way-genre a", text: genres(:large_literature).name

      # いちばん上にいて、十分に下げたら閉じる(開閉の印も戻る)
      page.execute_script("document.querySelector('#search-way-genre').scrollTop = 0")
      swipe_down("#search-way-genre", 220, duration: 400)
      assert_no_selector "#search-way-genre a", text: genres(:large_literature).name
      assert_selector ".search-ways__toggle[aria-expanded='false']", text: I18n.t("layouts.nav.genres")
    end
  end

  private

  def swipe_down(selector, distance, duration:)
    page.evaluate_async_script(<<~JS, selector, distance, duration)
      const [selector, distance, duration, done] = arguments
      const el = document.querySelector(selector)
      const rect = el.getBoundingClientRect()
      const x = rect.left + 100
      const y0 = rect.top + 60
      const touch = (type, y) => {
        const event = new Event(type, { bubbles: true, cancelable: true })
        Object.defineProperty(event, "touches", { value: type === "touchend" ? [] : [{ clientX: x, clientY: y }] })
        return event
      }
      const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
      ;(async () => {
        const steps = 10
        el.dispatchEvent(touch("touchstart", y0))
        for (let step = 1; step <= steps; step++) {
          await wait(duration / steps)
          el.dispatchEvent(touch("touchmove", y0 + (distance * step) / steps))
        }
        el.dispatchEvent(touch("touchend", y0 + distance))
        done()
      })()
    JS
  end
end
