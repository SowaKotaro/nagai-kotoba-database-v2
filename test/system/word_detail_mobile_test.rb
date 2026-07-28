require "application_system_test_case"

class WordDetailMobileTest < ApplicationSystemTestCase
  # 読みが長い語(= 円環交差数が大きい語)の詳細ページは、韻(ローマ字)・母音パターンが
  # 区切りの無い長大な英字列になる。語義カードはグリッド項目なので、折り返せない文字列が
  # あると min-width: auto で列幅ごと押し広げられ、モバイル幅で枠が画面からはみ出していた。
  test "読みが長い語の詳細ページはモバイル幅でも横にはみ出さない" do
    word = Word.create!(surface: "惑星ソラリスのラストの、びしょびしょの実家でびしょびしょの父親と抱き合うびしょびしょの主人公")
    word.word_senses.create!(
      reading: "ワクセイソラリスノラストノビショビショノジッカデビショビショノチチオヤトダキアウビショビショノシュジンコウ"
    )
    word.mark_annotated
    word.save!

    resize_window_to(390, 844)
    visit word_path(word)
    assert_selector ".sense-card"

    # ページ全体が横スクロールしない
    assert_equal page.evaluate_script("document.documentElement.clientWidth"),
                 page.evaluate_script("document.documentElement.scrollWidth"),
                 "ページが横方向にはみ出している"

    # 語義カードの右端が画面内に収まり、カード内にもはみ出した要素が無い
    overflow = page.evaluate_script(<<~JS)
      (() => {
        const vw = document.documentElement.clientWidth;
        const card = document.querySelector('.sense-card');
        const rect = card.getBoundingClientRect();
        const inner = [...card.querySelectorAll('*')]
          .filter(el => el.getBoundingClientRect().right > rect.right + 0.5)
          .map(el => el.tagName + '.' + el.className);
        return { over: Math.round(rect.right - vw), inner: inner };
      })()
    JS
    assert_operator overflow["over"], :<=, 0, "語義カードが画面右端からはみ出している"
    assert_empty overflow["inner"], "語義カード内に枠からはみ出した要素がある"
  end

  # ブラウザのセッション(ウィンドウ)は同一プロセス内の他テストと共有されるため、
  # 縮めたままにすると後続のテストがモバイル表示になって落ちる。必ず元の幅へ戻す。
  teardown do
    resize_window_to(*ApplicationSystemTestCase::DEFAULT_SCREEN_SIZE)
  end

  private

  def resize_window_to(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  end
end
