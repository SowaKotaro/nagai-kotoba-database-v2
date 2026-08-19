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

  test "末尾文字の単一ファセットは index + 動的見出し" do
    get words_path(last_char: "ン")
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "「ン」で終わる長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?last_char=%E3%83%B3"
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

  # 読みの文字数・モーラ数・言語的特徴は、値域が有限で「読みが15文字の長い言葉」のように
  # 本サイトの検索需要そのものになる面。統計・索引から常時リンクしているので index する。
  test "読みの文字数の単一ファセットは index + 動的見出し" do
    get words_path(reading_length: 7)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "読みが7文字の長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?reading_length=7"
  end

  test "モーラ数の単一ファセットは index + 動的見出し" do
    get words_path(mora_count: 12)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "12モーラの長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?mora_count=12"
  end

  test "言語的特徴の単一ファセットは index + 動的見出し" do
    feature = linguistic_features(:rendaku)
    get words_path(linguistic_feature_id: feature.id)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "#{feature.name}の長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?linguistic_feature_id=#{feature.id}"
  end

  # 範囲指定は値の取り方が無限にあり、内容も他の面と重なるためインデックスしない。
  test "読みの長さの範囲指定は noindex,follow" do
    get words_path(reading_length_min: 7)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  # シャッフルは並び違いの重複でしかないので index せず、クロールもさせない。
  test "シャッフルは noindex,follow で、ボタンにも nofollow が付く" do
    get words_path(sort: "shuffle")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select ".entry-toolbar__shuffle[rel=nofollow]", count: 1
  end

  test "検索フォーム(/search)は noindex,follow" do
    get search_path
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  # 条件を引き継ぐ /search?... はファセットの数だけ増えるので、クロールさせない。
  test "「検索条件を編集」リンクは nofollow" do
    get words_path(genre_id: genres(:large_literature).id)
    assert_response :success
    assert_select "a.active-facet__edit[rel=nofollow]", count: 1
  end
end
