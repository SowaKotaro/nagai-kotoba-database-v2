require "application_system_test_case"

# 下へ送ると流れ去るヘッダーを、上へ少し戻したときに降ろす(header-reveal。docs/design.md §5.1)。
# 位置は実ブラウザでしか確かめられない: ページの頭では流れる位置のまま、流れ去ったあとは画面の外で留まり、
# 上へ一定の距離を戻すと上端から降りて、下へ送ると畳まれる。ドロワーを開いている間は出したままにする。
class HeaderRevealTest < ApplicationSystemTestCase
  test "ヘッダーは、下へ送ると流れ去り、上へ少し戻すと降りて、下へ送ると畳まれる" do
    with_window_size(390, 844) do
      visit words_path
      wait_for_stimulus "header-reveal", selector: ".site-header"
      # 一覧が短くてもスクロールできるように、本文を縦に伸ばす
      page.execute_script("document.querySelector('main').style.minHeight = '4000px'")
      height = page.evaluate_script("Math.ceil(document.querySelector('.site-header').getBoundingClientRect().height)")

      # ページの頭では、流れる位置のまま(スクロールに合わせて上へ流れる)
      assert_header_top 0
      scroll_to_y 30
      assert_header_top(-30)
      assert_no_selector ".site-header.is-revealed"

      # 流れ去ると、ちょうど画面の外で留まる。24px に満たない戻しでは降りない
      scroll_to_y 600
      assert_header_top(-height)
      scroll_to_y 585
      assert_no_selector ".site-header.is-revealed"
      assert_header_top(-height)

      # 続けて 24px 以上戻すと、上端から降りてくる
      scroll_to_y 540
      assert_selector ".site-header.is-revealed"
      assert_header_top 0

      # 下へ送ると畳まれ、また戻すと降りる
      scroll_to_y 600
      assert_no_selector ".site-header.is-revealed"
      assert_header_top(-height)
      scroll_to_y 500
      assert_selector ".site-header.is-revealed"

      # ドロワーを開いている間は、下へ送られても出したまま(× のハンバーガーがドロワーの頭と同じ高さに並ぶ)
      find(".nav-toggle").click
      assert_selector ".nav-toggle[aria-expanded='true']"
      scroll_to_y 700
      assert_selector ".site-header.is-revealed"
      assert_header_top 0
      find(".nav-toggle").click
      assert_selector ".nav-toggle[aria-expanded='false']"

      # ページの頭まで戻ると、流れる位置に戻る
      scroll_to_y 0
      assert_no_selector ".site-header.is-revealed"
      assert_header_top 0
    end
  end

  private

  # スクロールして、2 フレーム待つ(コントローラはフレームごとにまとめて処理するので、待たずに次へ進むと取りこぼす)
  def scroll_to_y(y)
    page.execute_script("window.scrollTo(0, #{y})")
    page.evaluate_async_script("requestAnimationFrame(() => requestAnimationFrame(arguments[0]))")
  end

  # ヘッダーの上端(画面の上端からの px)が期待の値になるまで待つ。降りる動きは 280ms かかる
  def assert_header_top(expected)
    page.document.synchronize do
      top = page.evaluate_script("Math.round(document.querySelector('.site-header').getBoundingClientRect().top)")
      raise Capybara::ExpectationNotMet, "ヘッダーの上端は #{top}px(期待は #{expected}px)" unless top == expected
    end
  end
end
