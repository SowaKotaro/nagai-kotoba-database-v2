require "application_system_test_case"

# 詳細検索の「読みの文字数」スライダー(range_slider)。つまみの位置から、表示の文言と
# 送信する hidden(reading_length_min / reading_length_max)を JS が組み立てる。上限 30 は「以上」の意味なので
# max は空にする。文言は 3 種類(「N文字以上」「N文字」「N文字以上M文字以下」)。
class SearchLengthSliderTest < ApplicationSystemTestCase
  MESSAGE = "[data-range-slider-target='message']".freeze

  # つまみを動かす。range のネイティブ操作は環境で揺れるので、値を入れて input を発火させる。
  def slide(target, value)
    execute_script(<<~JS, find("[data-range-slider-target='#{target}']"), value)
      arguments[0].value = arguments[1];
      arguments[0].dispatchEvent(new Event("input", { bubbles: true }));
    JS
  end

  def hidden_values
    [ find("#reading_length_min", visible: false).value, find("#reading_length_max", visible: false).value ]
  end

  test "つまみの位置から文言と hidden の値を組み立てる(上限 30 は max を空にする)" do
    visit search_path
    wait_for_stimulus("range-slider")

    assert_selector MESSAGE, exact_text: "10文字以上"
    assert_equal [ "10", "" ], hidden_values

    slide("minThumb", 15)
    slide("maxThumb", 20)
    assert_selector MESSAGE, exact_text: "15文字以上20文字以下"
    assert_equal %w[15 20], hidden_values

    slide("minThumb", 20)
    assert_selector MESSAGE, exact_text: "20文字"
    assert_equal %w[20 20], hidden_values

    # 下限のつまみが上限を追い越したら、上限も連れて動く
    slide("minThumb", 25)
    assert_selector MESSAGE, exact_text: "25文字"
    assert_equal %w[25 25], hidden_values

    slide("maxThumb", 30)
    assert_selector MESSAGE, exact_text: "25文字以上"
    assert_equal [ "25", "" ], hidden_values
  end
end
