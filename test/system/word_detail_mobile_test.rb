require "application_system_test_case"

class WordDetailMobileTest < ApplicationSystemTestCase
  SURFACE = "惑星ソラリスのラストの、びしょびしょの実家でびしょびしょの父親と抱き合うびしょびしょの主人公".freeze
  READING = "ワクセイソラリスノラストノビショビショノジッカデビショビショノチチオヤトダキアウビショビショノシュジンコウ".freeze

  # ブラウザのセッション(ウィンドウ)は同一プロセス内の他テストと共有されるため、
  # 縮めたままにすると後続のテストがモバイル表示になって落ちる。必ず元の幅へ戻す。
  teardown do
    resize_window_to(*ApplicationSystemTestCase::DEFAULT_SCREEN_SIZE)
  end

  # 読みが長い語(= 円環交差数が大きい語)の詳細ページは、韻(ローマ字)・母音パターンが区切りの無い
  # 長大な英字列になる。語義カードはグリッド項目なので、折り返せない文字列があると min-width: auto で
  # 列幅ごと押し広げられ、モバイル幅で枠が画面からはみ出していた(PR #114)。
  #
  # また WebKit(iPhone Safari)は「見出し語まるごとに読み 1 つ」のルビの途中では改行できず、読みが長い語では
  # 見出しが 1 行のまま画面外へはみ出す。CSS で折り返させる手段が無いので、見出しと別表記の読みは
  # ルビ配置をやめて上下 2 段に積んでいる(PR #116。components.css の .sense-heading ruby)。
  # このテストは Chrome で動き、Chrome はルビの途中で改行できてはみ出し自体は再現しないため、
  # 「読みが丸ごと表記の上に積まれていること」を見る。
  test "読みが長い語の詳細ページはモバイル幅でも横にはみ出さず、読みは表記の上に丸ごと積まれる" do
    word = Word.create!(surface: SURFACE)
    sense = word.word_senses.create!(reading: READING)
    sense.word_sense_variants.create!(surface: SURFACE.sub("抱き合う", "抱きあう"), reading: READING)
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

    assert_reading_stacked ".sense-heading ruby", "語義見出し"
    assert_reading_stacked ".variant-list ruby", "別表記"
  end

  private

  # ルビが「読みが表記の上に丸ごと積まれた 2 段組」で描かれていることを確かめる。
  # ルビ配置に戻ると読みは表記の各行に散らばるので、読みの下端が表記の上端より下になる。
  def assert_reading_stacked(selector, label)
    assert_selector selector
    layout = page.evaluate_script(<<~JS, selector)
      ((selector) => {
        const ruby = document.querySelector(selector);
        const reading = ruby.querySelector('rt');
        // 表記(ルビのベース)は無名のテキストノードなので Range で位置を採る
        const surface = document.createRange();
        surface.selectNodeContents(ruby.firstChild);
        const lines = document.createRange();
        lines.selectNodeContents(reading);
        return {
          readingBottom: reading.getBoundingClientRect().bottom,
          surfaceTop: surface.getBoundingClientRect().top,
          readingLines: lines.getClientRects().length
        };
      })(arguments[0])
    JS

    assert_operator layout["readingBottom"], :<=, layout["surfaceTop"] + 1,
                    "#{label}の読みが表記の上に積まれていない(ルビ配置のままだと iPhone Safari で横にはみ出す)"
    assert_operator layout["readingLines"], :>=, 2, "#{label}の長い読みが折り返されていない"
  end
end
