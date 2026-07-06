require "test_helper"

# ファセット付き一覧のインデックス方針(Issue 17)の結合テスト。
class FacetIndexingTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "素の一覧(1ページ目)は index で canonical は /words" do
    get words_path
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: I18n.t("words.index.title")
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words"
  end

  test "単一ジャンルのファセット(1ページ目)は index + 動的見出し" do
    genre = genres(:large_literature)
    get words_path(genre_id: genre.id)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "文学の長い言葉"
    assert_select "title", text: "文学の長い言葉 | #{I18n.t('layouts.brand')}"
    assert_select "meta[name=description][content=?]",
      I18n.t("words.index.facet_description", label: "文学の長い言葉")
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?genre_id=#{genre.id}"
  end

  test "先頭文字の単一ファセットは index + 動的見出し" do
    get words_path(first_char: "カ")
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "「カ」から始まる長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?first_char=%E3%82%AB"
  end

  test "複数条件は noindex,follow で見出しは既定" do
    get words_path(genre_id: genres(:large_literature).id, first_char: "カ")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "h1.page-title", text: I18n.t("words.index.title")
  end

  test "キーワード検索は noindex,follow" do
    get words_path(q: "カレー")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  test "2ページ目以降は noindex,follow で canonical に page を含む" do
    get words_path(page: 2)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?page=2"
  end

  test "読みの長さ単独はインデックス対象ファセットではなく noindex,follow" do
    get words_path(reading_length: 7)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  test "検索フォーム(/search)は noindex,follow" do
    get search_path
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end
end
