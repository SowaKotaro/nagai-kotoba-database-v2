require "application_system_test_case"

# 詳細検索のフォームで、実ブラウザでしか確かめられないもの(1 回の visit でまとめて確かめる)。
# - 送信の行の貼り付き(CSS の position: sticky): 条件の区画を開いてフォームが画面より長くなっても、
#   送信ボタンはフォームの終わりまでスクロールしなくても画面の下端に見えている。
# - 「読みの文字数」スライダー(range_slider): つまみの位置から、表示の文言と送信する hidden
#   (reading_length_min / reading_length_max)を組み立て、トラックの上の棒グラフのうち範囲に入る棒を濃くする。
#   上限 30 は「以上」の意味なので max を、下限 10(収録基準)は絞っていないので min を空にする。
#   文言は 3 種類(「N文字以上」「N文字」「N文字以上M文字以下」)。
# - 選択数のバッジ(fold_count): 畳んだままでも選択が分かるよう、ジャンルの大分類の折り畳みと、それを囲む条件の区画の
#   見出しに配下の選択数を出す。
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

  test "区画を開いても送信の行が画面の下端に貼り付き、スライダーの文言と hidden の値(上限 30 は max を空にする)と、選択数のバッジを組み立てる" do
    visit search_path
    wait_for_stimulus("range-slider")

    # 条件の区画は畳んで描かれる。全部開いて、画面より長いフォームにする(開閉そのものはブラウザ標準の details)
    execute_script('document.querySelectorAll(".search-section").forEach((section) => { section.open = true })')
    layout = submit_row_layout
    assert_operator layout["formBottom"], :>, layout["viewport"], "フォームが画面に収まっていて、貼り付きを確かめられない"
    assert_in_delta layout["viewport"], layout["rowBottom"], 1, "送信の行が画面の下端に貼り付いていない"

    assert_selector MESSAGE, exact_text: "10文字以上"
    assert_equal [ "", "" ], hidden_values

    slide("minThumb", 15)
    slide("maxThumb", 20)
    assert_selector MESSAGE, exact_text: "15文字以上20文字以下"
    assert_equal %w[15 20], hidden_values
    assert_equal (15..20).map(&:to_s), all(".length-slider__bar.is-selected", visible: :all).map { |bar| bar["data-value"] }

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

    # 両端に戻すと、どちらも送らない(絞っていない)
    slide("minThumb", 10)
    assert_equal [ "", "" ], hidden_values

    # ジャンル: 小分類を選ぶと、それを含む区画・大分類の見出しに 1 が出て、外すと消える
    wait_for_stimulus("fold-count")
    folds = [ WordSense.human_attribute_name(:genre), genres(:large_literature).name ]
    checkbox = find("input[name='genre_id[]'][value='#{genres(:small_novel).id}']", visible: :all)
    execute_script("arguments[0].click()", checkbox)
    folds.each { |name| assert_equal [ "1", false ], badge_state(name), name }

    execute_script("arguments[0].click()", checkbox)
    folds.each { |name| assert_equal [ "", true ], badge_state(name), name }
  end

  private

  # 画面の高さと、フォームの下端・送信の行(.search-actions)の下端の、画面上の位置
  def submit_row_layout
    evaluate_script(<<~JS)
      (() => {
        const form = document.querySelector(".search-form").getBoundingClientRect()
        const row = document.querySelector(".search-actions").getBoundingClientRect()
        return { viewport: document.documentElement.clientHeight, formBottom: form.bottom, rowBottom: row.bottom }
      })()
    JS
  end

  # 見出しが name の折り畳み(details)にあるバッジの [文字, hidden か]。畳まれていて見えなくても読む。
  def badge_state(name)
    evaluate_script(<<~JS, name)
      (() => {
        const summary = [ ...document.querySelectorAll("details > summary") ]
          .find((element) => element.querySelector("span")?.textContent.trim() === arguments[0])
        const badge = summary.querySelector("[data-fold-count-target='count']")
        return [ badge.textContent.trim(), badge.hidden ]
      })()
    JS
  end
end
