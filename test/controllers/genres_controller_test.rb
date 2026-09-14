require "test_helper"

# ジャンル階層のハブ(/genres。Issue 21)。件数の積み上げは GenresHelperTest で見る。
class GenresControllerTest < ActionDispatch::IntegrationTest
  test "ジャンルハブは誰でも見られ(index 可)、各分類が公開件数つきで絞り込みへリンクする" do
    get genres_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("genres.index.title")
    assert_select "meta[name=robots]", count: 0

    # 大分類 文学(公開1件・murder 経由)は折り畳み(summary)。絞り込みは「全体を見る」リンク
    assert_select "details.genre-hub__fold summary .genre-hub__large-name", text: "文学"
    assert_select "a.genre-hub__whole[href=?]", words_path(genre_id: genres(:large_literature).id),
                  text: Regexp.new(I18n.t("genres.index.whole", name: "文学"))
    # 中分類 日本文学・小分類 小説と、その件数(1)
    assert_select "a[href=?]", words_path(genre_id: genres(:medium_japanese).id), text: "日本文学"
    assert_select "a.genre-hub__small[href=?]", words_path(genre_id: genres(:small_novel).id)
    assert_select ".genre-hub__count", text: "1"
  end
end
