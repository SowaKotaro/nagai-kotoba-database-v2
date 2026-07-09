require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # 遅延読み込み(importmap)や fetch を挟む UI が多いため、既定の2秒より長めに待つ。
  Capybara.default_max_wait_time = 5

  # ヘッドレスで実行する(CI・WSL などディスプレイの無い環境でも動かすため)。
  # Chrome が PATH に無い環境(WSL 等)では CHROME_BIN で Chrome for Testing などの
  # バイナリを指定できる(CI は google-chrome-stable を使うので未指定のまま)。
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"].present?
    # confirm ダイアログをドライバに自動で閉じさせない。既定の "dismiss and notify" だと
    # turbo_confirm の confirm() が false を返し、Turbo が送信をイベントも例外も出さずに
    # 中止するため、テストからは「押しても何も起きない」ようにしか見えなくなる。
    # 注意: Chrome 150.0.7871.115 では :ignore を渡しても WebDriver コマンド実行中に
    # 開いたダイアログは false で自動クローズされる(実ダイアログ依存のテストは書けない。
    # confirm の検証は click_accepting_confirm を使うこと)。コマンド外で開いた
    # ダイアログへの保険として残している。
    options.unhandled_prompt_behavior = :ignore
    # ヘッドレスの定番安定化(共有メモリ・GPU 由来の不安定さを避ける)
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    # Web フォント(Google Fonts)を読み込ませない。読み込み完了時の再レイアウトで
    # クリック座標がずれて flaky になるのを防ぐ(外部ネットワークにも依存しない)。
    options.add_argument("--host-resolver-rules=MAP fonts.googleapis.com 127.0.0.1, MAP fonts.gstatic.com 127.0.0.1")
  end

  # 指定の Stimulus コントローラが要素に接続されるまで待つ。
  # importmap + lazyLoadControllersFrom は ES モジュールを遅延読み込みするため、
  # 接続前にクリックすると操作が失われて flaky になる。JS 操作の前に必ず待つこと。
  def wait_for_stimulus(identifier, selector: "[data-controller~='#{identifier}']")
    script = <<~JS
      (() => {
        const el = document.querySelector(#{selector.to_json});
        return !!(el && window.Stimulus &&
                  window.Stimulus.getControllerForElementAndIdentifier(el, #{identifier.to_json}));
      })()
    JS
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time * 3
    until page.evaluate_script(script)
      flunk "Stimulus コントローラ #{identifier} が接続されませんでした" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
  end

  # クリックして期待する状態(expect_css + text:/count: 等)が現れるまで待つ。
  # ブロックはクリック対象の要素を返すファインダ。まずネイティブクリックを試し、
  # 反応が無ければ JS の click()(仕様上 activation を発火する)でフォールバックする。
  # このヘッドレス環境ではネイティブクリックがまれに要素へ届かないための保険。
  # **押し直しても安全(冪等)な操作にだけ使う。**
  def click_expecting(expect_css:, **expect_options, &element_finder)
    element = element_finder.call
    # sticky ヘッダー下に隠れないよう画面中央へ出してからクリックする
    page.scroll_to(element, align: :center)
    element.click
    return if has_selector?(expect_css, **expect_options)

    page.execute_script("arguments[0].click()", element_finder.call)
    assert_selector expect_css, **expect_options
  end

  # turbo_confirm 付きの操作を実行して承認する。実ダイアログには依存しない:
  # Chrome 150.0.7871.114 以降、WebDriver コマンド中に開いたダイアログは
  # unhandled_prompt_behavior に関わらず自動で閉じられることがあり(.115 で確認)、
  # 実ダイアログを待つテストは Chrome のパッチごとに壊れるため。
  # 代わりに window.confirm をスタブして「呼ばれたこと」とメッセージを検証し、
  # true を返して操作を続行させる。クリックはネイティブクリックが要素に届かない
  # 環境(Issue 40)でも確実に発火する JS click で行う。
  def click_accepting_confirm(message, &element_finder)
    element = element_finder.call
    page.scroll_to(element, align: :center)
    page.execute_script(<<~JS, element)
      window.__lastConfirmMessage = null;
      window.confirm = (msg) => { window.__lastConfirmMessage = msg; return true; };
      arguments[0].click();
    JS
    assert wait_until { page.evaluate_script("window.__lastConfirmMessage") },
           "confirm ダイアログ(#{message})が表示されませんでした"
    assert_equal message, page.evaluate_script("window.__lastConfirmMessage")
  end

  # 条件が真になるまで待つ(DB の反映待ちなど、Capybara のリトライに乗らない条件用)。
  def wait_until(timeout: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.2
    end
  end

  # <details> パネルを開く。chromedriver のネイティブクリックが summary のトグルに
  # 効かないことがある(環境依存)ため、開かなければ JS で開く。
  # ネイティブクリックでの開閉自体は用語解説パネルのテストで別途担保している。
  def open_details(selector)
    find("#{selector} summary").click
    return if has_css?("#{selector}[open]", wait: 2)

    execute_script("document.querySelector(#{selector.to_json}).open = true")
    assert_selector "#{selector}[open]"
  end

  # 管理画面のシステムテスト用: ログインフォームから管理者でサインインする。
  def system_sign_in(admin = admins(:one), password: "password")
    visit new_session_path
    fill_in "username", with: admin.username
    fill_in "password", with: password
    click_on I18n.t("sessions.new.submit")
    # ログイン完了(リダイレクト)を待ってから次の操作へ進む
    assert_no_current_path new_session_path
  end
end
