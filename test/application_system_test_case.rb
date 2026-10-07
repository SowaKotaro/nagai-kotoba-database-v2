require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # 遅延読み込み(importmap)や fetch を挟む UI が多いため、既定の2秒より長めに待つ。
  Capybara.default_max_wait_time = 5

  # 既定のウィンドウ幅。with_window_size が元に戻すときにも使う。
  DEFAULT_SCREEN_SIZE = [ 1400, 1400 ].freeze

  # ヘッドレスで実行する(CI・WSL などディスプレイの無い環境でも動かすため)。
  # Chrome が PATH に無い環境(WSL 等)では CHROME_BIN で Chrome for Testing などの
  # バイナリを指定できる(CI は google-chrome-stable を使うので未指定のまま)。
  driven_by :selenium, using: :headless_chrome, screen_size: DEFAULT_SCREEN_SIZE do |options|
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
    # Web フォント(Google Fonts)への接続を塞ぐ。アプリはもう web フォントを読まない(CLAUDE.md)ので、
    # いまは何も遮っていない。外部のフォントを読む変更が入ったときに、読み込み完了時の再レイアウトで
    # クリック座標がずれて flaky になるのと、テストが外部ネットワークに依存するのを防ぐ保険として残している。
    options.add_argument("--host-resolver-rules=MAP fonts.googleapis.com 127.0.0.1, MAP fonts.gstatic.com 127.0.0.1")
    # パスワード漏洩の警告を切る。fixture の管理者のパスワード("password")でログインすると、Chrome が
    # 「漏洩したパスワード」の警告を出して入力を奪い、以後ネイティブの入力(fill_in・send_keys・クリック)が
    # ページに届かなくなる(下の「入力手段についての注記」)。切れるのはこの設定だけで、
    # --disable-features=PasswordLeakDetection や credentials_enable_service では切れなかった
    # (password_manager_enabled は効いたり効かなかったりした。2026-10-07、Chrome 155.0.8059.39)。
    options.add_preference("profile.password_manager_leak_detection", false)
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
  # ネイティブクリックが要素に届かなかったときの保険(届かなかった主な原因のパスワード漏洩の警告は、
  # 上の driven_by で切ってある)。**押し直しても安全(冪等)な操作にだけ使う。**
  def click_expecting(expect_css:, **expect_options, &element_finder)
    element = element_finder.call
    # 画面下端に sticky で貼り付く操作バー(.ann-actionbar・.cand-bar)の下に隠れないよう、
    # 画面中央へ出してからクリックする(ヘッダーは sticky ではない)
    page.scroll_to(element, align: :center)
    element.click
    return if has_selector?(expect_css, **expect_options)

    page.execute_script("arguments[0].click()", element_finder.call)
    assert_selector expect_css, **expect_options
  end

  # JS の click() だけで押す(ネイティブクリックを使わない)。
  # click_expecting は反応が無いとき JS click で押し直すが、届かなかったはずのネイティブクリックが
  # **後の操作(send_keys など)のあとに遅れて届く**ことがあった(パスワード漏洩の警告を切る前に見た現象)。
  # 「＋追加」のように、押し直されると直後の結果表示を消してしまう操作はこちらで 1 回だけ押す。
  def click_via_js(expect_css:, **expect_options, &element_finder)
    element = element_finder.call
    page.scroll_to(element, align: :center)
    page.execute_script("arguments[0].click()", element)
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
  # 開閉そのものはブラウザ標準の挙動なので、中身を操作できる状態にすることだけを目的にする。
  def open_details(selector)
    find("#{selector} summary").click
    return if has_css?("#{selector}[open]", wait: 2)

    execute_script("document.querySelector(#{selector.to_json}).open = true")
    assert_selector "#{selector}[open]"
  end

  # チップの input は視覚的に隠れているため、ネイティブクリックに頼らず
  # 選択して change を発火させる(ヘッドレスでの取りこぼしを避ける)。
  def choose_hidden_input(selector)
    input = find(selector, visible: false)
    execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", input)
  end

  # ウィンドウ幅をブロックの間だけ変える(モバイル表示の確認)。ブラウザのセッション(ウィンドウ)は同じプロセスの
  # 他のテストと共有されるので、縮めたままにすると後続のテストがモバイル表示になって落ちる。必ず元の幅へ戻す。
  def with_window_size(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
    yield
  ensure
    page.driver.browser.manage.window.resize_to(*DEFAULT_SCREEN_SIZE)
  end

  # 入力欄に値を JS で流し込み、input イベントを送る(Stimulus の入力の検証などを走らせる)。
  # target は CSS セレクタか要素。打鍵の手順そのものではなく「この値になったとき」を確かめたいときに使う。
  def set_value_via_js(target, text)
    element = target.is_a?(String) ? find(target) : target
    execute_script(<<~JS, element, text)
      arguments[0].value = arguments[1];
      arguments[0].dispatchEvent(new Event("input", { bubbles: true }));
    JS
  end

  # フォーカスのある要素へ keydown を JS で送る(キーボードの操作の受け口を確かめる)。
  def press_key(key, ctrl: false)
    execute_script(<<~JS, key, ctrl)
      const [key, ctrlKey] = arguments;
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key, ctrlKey, bubbles: true, cancelable: true }));
    JS
  end

  # 要素へ click の MouseEvent を JS で送る。Shift+クリックを、修飾キーの状態ごと 1 回で送れる。
  def dispatch_click(element, shift: false)
    execute_script("arguments[0].dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, shiftKey: arguments[1] }))",
                   element, shift)
  end

  # 入力手段についての注記はここだけに置く(2026-10-07、Chrome 155.0.8059.39 のヘッドレスで確かめた):
  # - ログインの前も後も、日本語・ASCII の fill_in / send_keys、ネイティブのクリックとキー入力はページに届く。
  # - 以前はログイン後に届かなかった(fill_in・send_keys・クリックとも)。fixture の管理者のパスワード
  #   ("password")で Chrome のパスワード漏洩の警告が出て、入力を奪っていたため。上の driven_by で切ってある。
  # - そのころに書いたテストには、値を JS で流し込む・keydown を JS で送る・JS の click() で押す書き方が残る。
  #   どれもそのままで正しく動く。新しく書くときの使い分け:
  #   押し直しても結果が同じ操作は click_expecting、押し直すと困る操作は click_via_js、turbo_confirm の付いた操作は
  #   click_accepting_confirm、開閉のトグルは素のクリック、視覚的に隠れた input は choose_hidden_input、
  #   値になったときの振る舞いだけを見たい入力は set_value_via_js、Shift つきのクリックは dispatch_click、
  #   フォーカス先へのキーは press_key、ウィンドウ幅を変えるときは with_window_size。
  #
  # 管理画面のシステムテスト用: ログインフォームから管理者でサインインする。
  def system_sign_in(admin = admins(:one), password: "password")
    visit new_session_path
    fill_in "username", with: admin.username
    fill_in "password", with: password
    # ネイティブクリックだと送信ボタンに届かずログイン画面に留まることがある(2026-09-23 に再現)。
    # 送信は何度押しても結果が同じとは限らない(遅れて届くと二重送信になる)ので、JS の click() だけで押す。
    execute_script("arguments[0].click()", find_button(I18n.t("sessions.new.submit")))
    # ログイン完了(リダイレクト)を待ってから次の操作へ進む
    assert_no_current_path new_session_path
  end
end
