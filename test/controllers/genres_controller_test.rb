require "test_helper"

# ジャンル階層のハブ(/genres。Issue 21)。件数の積み上げは GenresHelperTest で見る。
# 名前で絞り込む欄の動き(JS)は SearchHubsTest(system)で見る。
class GenresControllerTest < ActionDispatch::IntegrationTest
  test "ジャンルハブは誰でも見られ(index 可)、各分類が公開件数つきで絞り込みへリンクし、名前で絞り込める" do
    # 名前に「・」を含む大分類(公開語のある小分類を 1 つ持つ)
    large = Genre.create!(name: "芸術・音楽", level: :large)
    small = Genre.create!(name: "楽曲", parent: Genre.create!(name: "音楽", parent: large, level: :medium), level: :small)
    create_published_word(surface: "長い楽曲の名前", reading: "ナガイガッキョクノナマエ", genre: small)

    get genres_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("genres.index.title")
    assert_select "title", text: "#{I18n.t('genres.index.meta_title')} | #{I18n.t('layouts.brand')}" # <title> だけは何のページかまで言う
    assert_select "meta[name=robots]", count: 0

    # 大分類 文学(公開1件・murder 経由)は折り畳み(summary)。絞り込みは「全体を見る」リンク
    assert_select "details.genre-hub__fold summary .genre-hub__large-name", text: "文学"
    assert_select "a.genre-hub__whole[href=?]", words_path(genre_id: genres(:large_literature).id),
                  text: Regexp.new(I18n.t("genres.index.whole", name: "文学"))
    # 中分類 日本文学・小分類 小説と、その件数(1)
    assert_select "a[href=?]", words_path(genre_id: genres(:medium_japanese).id), text: "日本文学"
    assert_select "a.genre-hub__small[href=?]", words_path(genre_id: genres(:small_novel).id)
    assert_select ".genre-hub__count", text: "1"
    # 大分類の名前は「・」の後ろでだけ折れる(wbr を挟む)
    assert_select ".genre-hub__large-name", text: "芸術・音楽" do
      assert_select "wbr", count: 1
    end

    # 名前で絞り込む欄は JS がつながってから出す(hidden で描く)。絞り込む単位は小分類で、中分類の名前でも当たる
    assert_select "[data-controller=list-filter]" do
      assert_select ".list-filter[hidden] input[type=search][aria-label=?]", I18n.t("genres.index.filter_label")
      assert_select "details[data-list-filter-target=group] .genre-hub__medium[data-list-filter-target=group]"
      assert_select "li[data-list-filter-target=item][data-filter-terms=?]", "日本文学 小説"
    end
  end
end
