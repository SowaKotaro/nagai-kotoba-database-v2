require "test_helper"

# 50音・読みの文字数の索引(/browse。Issue 22)。件数の集計は PublishedSenseCountsTest で見る。
class BrowseControllerTest < ActionDispatch::IntegrationTest
  test "索引は誰でも見られ(index 可)、公開語義のある文字・文字数だけが件数つきで絞り込みへリンクする" do
    get browse_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("browse.index.title")
    assert_select "meta[name=robots]", count: 0

    # カ(curry の読み カレー)→ 先頭文字の絞り込み。件数は50音表の整列を崩さないよう、
    # セルに文字で並べずヒートと title(ホバー)で示す
    assert_select "a.kana-cell--link[href=?]", words_path(first_char: "カ")
    assert_select "a.kana-cell--heat[href=?][title]", words_path(first_char: "カ")
    # 公開語義が無い先頭文字はリンクにせず、沈めて表示する
    assert_select "a.kana-cell--link[href=?]", words_path(first_char: "ヲ"), count: 0
    assert_select ".kana-cell--muted", minimum: 1

    # 読みの文字数 3(カレー)・7(さつじんじけん)→ 文字数の絞り込み。件数は「件」単位で条件の数字と区別する
    assert_select "a.browse-length[href=?]", words_path(reading_length: 3)
    assert_select "a.browse-length[href=?]", words_path(reading_length: 7)
    assert_select ".browse-length__count", text: /\A\d+件\z/, minimum: 1
  end
end
