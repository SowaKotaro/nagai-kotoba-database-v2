require "application_system_test_case"

# 詳細検索のフォームで JS が組み立てるもの(1 回の visit でまとめて確かめる)。
# - 「読みの文字数」スライダー(range_slider): つまみの位置から、表示の文言と送信する hidden
#   (reading_length_min / reading_length_max)を組み立てる。上限 30 は「以上」の意味なので max は空にする。
#   文言は 3 種類(「N文字以上」「N文字」「N文字以上M文字以下」)。
# - ジャンルの絞り込み(genre_filter): 畳んだままでも選択が分かるよう、各折り畳みの見出しに配下の選択数を出す。
class SearchFormTest < ApplicationSystemTestCase
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

  test "スライダーの文言と hidden の値(上限 30 は max を空にする)と、ジャンルの選択数のバッジを組み立てる" do
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

    # ジャンル: 小分類を選ぶと、それを含む大分類・中分類の見出しに 1 が出て、外すと消える
    wait_for_stimulus("genre-filter")
    large, medium, small = genres(:large_literature), genres(:medium_japanese), genres(:small_novel)
    checkbox = find("input[name='genre_id[]'][value='#{small.id}']", visible: :all)
    execute_script("arguments[0].click()", checkbox)
    assert_equal [ "1", false ], badge_state(large)
    assert_equal [ "1", false ], badge_state(medium)

    execute_script("arguments[0].click()", checkbox)
    assert_equal [ "", true ], badge_state(large)
    assert_equal [ "", true ], badge_state(medium)
  end

  private

  # その折り畳み(details)の見出しにあるバッジの [文字, hidden か]。畳まれていて見えなくても読む。
  def badge_state(genre)
    evaluate_script(<<~JS, genre.name)
      (() => {
        const summary = [ ...document.querySelectorAll("details > summary") ]
          .find((element) => element.querySelector("span")?.textContent.trim() === arguments[0])
        const badge = summary.querySelector("[data-genre-filter-target='count']")
        return [ badge.textContent.trim(), badge.hidden ]
      })()
    JS
  end
end
