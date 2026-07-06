require "test_helper"

class GenresControllerTest < ActionDispatch::IntegrationTest
  test "ジャンルハブは未認証で閲覧でき index 可能" do
    get genres_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("genres.index.title")
    assert_select "meta[name=robots]", count: 0
  end

  test "各分類が公開件数つきで単語一覧の絞り込みへリンクする" do
    get genres_path
    # 大分類 文学(公開1件・murder 経由)へのリンク
    assert_select "a[href=?]", words_path(genre_id: genres(:large_literature).id), text: "文学"
    # 中分類 日本文学
    assert_select "a[href=?]", words_path(genre_id: genres(:medium_japanese).id), text: "日本文学"
    # 小分類 小説(墨枠タグ)
    assert_select "a.genre-hub__small[href=?]", words_path(genre_id: genres(:small_novel).id)
    # 件数(1)が表示される
    assert_select ".genre-hub__count", text: "1"
  end

  test "ヘッダーとフッターからジャンルへ恒久リンクされている" do
    get root_path
    assert_select "header a[href=?]", genres_path, text: I18n.t("layouts.nav.genres")
    assert_select "footer a[href=?]", genres_path, text: I18n.t("layouts.nav.genres")
  end

  test "sitemap にジャンルハブが含まれる" do
    get "/sitemap.xml"
    assert_includes response.body, "<loc>https://nagai-kotoba-database.jp/genres</loc>"
  end
end
