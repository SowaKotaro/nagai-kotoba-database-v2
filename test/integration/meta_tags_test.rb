require "test_helper"

# レイアウトが出力する SEO / OGP メタ情報(Issue 14)の結合テスト。
class MetaTagsTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "トップページに既定の description・canonical・OGP が出力される" do
    get root_path
    assert_response :success

    assert_select "meta[name=description][content=?]", I18n.t("home.index.description")
    assert_select "link[rel=canonical][href=?]", "#{HOST}/"
    assert_select "meta[property='og:type'][content=?]", "website"
    assert_select "meta[property='og:site_name'][content=?]", I18n.t("layouts.brand")
    assert_select "meta[property='og:locale'][content=?]", "ja_JP"
    assert_select "meta[property='og:url'][content=?]", "#{HOST}/"
    assert_select "meta[property='og:image'][content=?]", "#{HOST}/og-default.png"
    assert_select "meta[property='og:image:width'][content=?]", "1200"
    assert_select "meta[property='og:image:height'][content=?]", "630"
    assert_select "meta[property='og:image:alt'][content=?]", I18n.t("layouts.og_image_alt")
    assert_select "meta[name='twitter:card'][content=?]", "summary_large_image"
    assert_select "meta[name='twitter:title'][content=?]", I18n.t("layouts.brand")
    assert_select "meta[name='twitter:description'][content=?]", I18n.t("home.index.description")
  end

  test "単語詳細の description はリード文、og:type は article、canonical は本番ホスト" do
    word = words(:abc_murder)
    get word_path(word)
    assert_response :success

    lead = "「ABC殺人事件」は、読み「さつじんじけん」（7文字・7モーラ）の日本語の長い言葉。" \
           "ジャンルは 文学 › 日本文学 › 小説。人を殺す事件"
    assert_select "meta[name=description][content=?]", lead
    assert_select "meta[property='og:description'][content=?]", lead
    assert_select "meta[property='og:type'][content=?]", "article"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words/#{word.id}"
    assert_select "meta[property='og:url'][content=?]", "#{HOST}/words/#{word.id}"
  end

  test "canonical はクエリパラメータを含めず現在のパスのみを使う(既定の挙動)" do
    # /words は Issue 17 で canonical を正規化上書きするため、上書きしない /search で既定挙動を確認する。
    get search_path(q: "テスト", genre_id: 1)
    assert_response :success
    assert_select "link[rel=canonical][href=?]", "#{HOST}/search"
  end
end
