require "application_system_test_case"

# 詳細検索の文字種キーボード。大文字小文字トグル(Aa)を切ると「a」キーが消え、組み立て済みの「a」も
# 「A」に畳む。区別しない条件で開いたときに最初から「a」キーが無いのはサーバ描画なので
# SearchesControllerTest で見る。
class SearchCharTypeTest < ApplicationSystemTestCase
  LOWER_KEY = "[data-char-type-target='lowerKey']".freeze

  # トグルは冪等でないので click_expecting は使わず素のクリックで検証する。
  # ボタンは aria-label に現在の状態を持つので、それを掴んで押す。
  def case_toggle(state)
    find("button[aria-label='#{I18n.t("searches.char_type_#{state}")}']")
  end

  test "大文字小文字を区別しないと「a」キーが隠れて「a」は「A」に畳まれ、戻すとキーだけ再び現れる" do
    visit search_path
    wait_for_stimulus("char-type")
    wait_for_stimulus("char-type-toggle")
    assert_selector LOWER_KEY, text: "a"

    find(".char-type-key", text: "A").click
    find(LOWER_KEY).click
    assert_selector ".char-type-display__value", text: "Aa"

    case_toggle(:case_sensitive).click
    assert_no_selector LOWER_KEY
    # 「A」キーは残る(a は A に畳まれるだけで、英字そのものは検索できる)
    assert_selector ".char-type-key", text: "A"
    assert_selector ".char-type-display__value", text: "AA"
    assert_equal "AA", find("#char_type_pattern", visible: false).value

    # トグルを戻すと「a」キーは現れるが、畳んだ「a」は戻さない
    case_toggle(:case_insensitive).click
    assert_selector LOWER_KEY, text: "a"
    assert_selector ".char-type-display__value", text: "AA"
  end
end
