require "application_system_test_case"

# ダークモードの切り替え(docs/design.md §9)。
# 「data-theme が付く」だけでなく、実際に地の色が変わることまで見る。
class ThemeToggleTest < ApplicationSystemTestCase
  # tokens.css の --bg / --dark-bg。トークンを変えたらここも合わせる
  LIGHT_BG = "rgb(250, 248, 244)".freeze
  DARK_BG = "rgb(23, 21, 15)".freeze

  # localStorage はセッションのリセットでは消えないため、テスト間で持ち越さない
  teardown do
    page.execute_script("window.localStorage.removeItem('theme')")
  rescue StandardError
    # ページを開かずに終わったテストでは触れないので無視してよい
  end

  test "トグルを押すとダークになり、再訪問しても維持される" do
    visit root_path
    wait_for_stimulus "theme"

    assert_equal LIGHT_BG, body_background, "初期状態は OS 設定(ヘッドレスは light)に従う"

    toggle_theme
    assert_equal DARK_BG, body_background
    assert_equal "dark", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "dark", page.evaluate_script("window.localStorage.getItem('theme')")

    # 再訪問時は head のインラインスクリプトが body の描画前に復元する(ちらつき防止)
    visit root_path
    assert_equal DARK_BG, body_background
    assert_selector ".theme-toggle__button[aria-checked='true']"
  end

  test "もう一度押すとライトに戻る" do
    visit root_path
    wait_for_stimulus "theme"

    toggle_theme
    assert_equal DARK_BG, body_background

    click_expecting(expect_css: ".theme-toggle__button[aria-checked='false']") { theme_button }
    assert_equal LIGHT_BG, body_background
    assert_equal "light", page.evaluate_script("window.localStorage.getItem('theme')")
  end

  test "手動で選んでいなければ OS のダーク設定に追従する" do
    emulate_prefers_color_scheme "dark"
    visit root_path
    wait_for_stimulus "theme"

    assert_equal DARK_BG, body_background, "OS 設定だけでダークになる(localStorage は空)"
    assert_nil page.evaluate_script("window.localStorage.getItem('theme')")
    assert_selector ".theme-toggle__button[aria-checked='true']", visible: :all

    # OS がダークでも、トグルを押せばライトに上書きできる
    click_expecting(expect_css: ".theme-toggle__button[aria-checked='false']") { theme_button }
    assert_equal LIGHT_BG, body_background
    assert_equal "light", page.evaluate_script("document.documentElement.dataset.theme")
  ensure
    emulate_prefers_color_scheme nil
  end

  private
    def theme_button
      find(".theme-toggle__button")
    end

    def toggle_theme
      click_expecting(expect_css: ".theme-toggle__button[aria-checked='true']") { theme_button }
    end

    def body_background
      page.evaluate_script("getComputedStyle(document.body).backgroundColor")
    end

    # OS のカラースキームの好みを CDP でエミュレートする(nil で解除)。
    def emulate_prefers_color_scheme(value)
      features = value ? [ { name: "prefers-color-scheme", value: value } ] : []
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", media: "", features: features)
    end
end
