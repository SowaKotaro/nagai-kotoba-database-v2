require "application_system_test_case"

# 詳細検索の文字種キーボード。大文字小文字トグル(Aa)を切ると「a」キーが消える。
class SearchCharTypeTest < ApplicationSystemTestCase
  LOWER_KEY = "[data-char-type-target='lowerKey']".freeze

  # トグルは冪等でないので click_expecting は使わず素のクリックで検証する。
  # ボタンは aria-label に現在の状態を持つので、それを掴んで押す。
  def case_toggle(state)
    find("button[aria-label='#{I18n.t("searches.char_type_#{state}")}']")
  end

  test "大文字小文字を区別しないとき「a」キーが隠れ、戻すと再び現れる" do
    visit search_path
    wait_for_stimulus("char-type")
    assert_selector LOWER_KEY, text: "a"

    case_toggle(:case_sensitive).click
    assert_no_selector LOWER_KEY
    # 「A」キーは残る(a は A に畳まれるだけで、英字そのものは検索できる)
    assert_selector ".char-type-key", text: "A"

    case_toggle(:case_insensitive).click
    assert_selector LOWER_KEY, text: "a"
  end

  test "大文字小文字を区別しないと、組み立て済みの「a」も「A」に畳まれる" do
    visit search_path
    wait_for_stimulus("char-type")
    find(".char-type-key", text: "A").click
    find(LOWER_KEY).click
    assert_selector ".char-type-display__value", text: "Aa"

    case_toggle(:case_sensitive).click
    assert_selector ".char-type-display__value", text: "AA"
    assert_equal "AA", find("#char_type_pattern", visible: false).value

    # 畳んだ「a」は戻さない(トグルを戻してもパターンは AA のまま)
    case_toggle(:case_insensitive).click
    assert_selector ".char-type-display__value", text: "AA"
  end

  test "大文字小文字を区別しない条件で開いたときは最初から「a」キーが無い" do
    visit search_path(char_type_pattern: "AA", char_type_ignore_case: "1")
    wait_for_stimulus("char-type")

    assert_no_selector LOWER_KEY
    assert_selector "button[aria-pressed='false'][aria-label='#{I18n.t("searches.char_type_case_insensitive")}']"
  end
end
