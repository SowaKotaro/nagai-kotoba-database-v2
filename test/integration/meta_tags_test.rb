require "test_helper"

# レイアウトが出力する SEO / OGP メタ情報(Issue 14)の結合テスト。
class MetaTagsTest < ActionDispatch::IntegrationTest
  test "トップ・一覧・検索フォームはそれぞれ固有の title・description・canonical・OGP を持つ" do
    get root_path
    assert_response :success

    title = "#{I18n.t('home.index.title_tagline')} | #{I18n.t('layouts.brand')}"
    assert_select "title", text: title
    assert_select "meta[name=description][content=?]", I18n.t("home.index.meta_description")
    assert_select "link[rel=canonical][href=?]", "#{CANONICAL_HOST}/"
    assert_select "meta[property='og:type'][content=?]", "website"
    assert_select "meta[property='og:site_name'][content=?]", I18n.t("layouts.brand")
    assert_select "meta[property='og:locale'][content=?]", "ja_JP"
    assert_select "meta[property='og:url'][content=?]", "#{CANONICAL_HOST}/"
    assert_select "meta[property='og:image'][content=?]", "#{CANONICAL_HOST}/og-default.png"
    assert_select "meta[property='og:image:width'][content=?]", "1200"
    assert_select "meta[property='og:image:height'][content=?]", "630"
    assert_select "meta[property='og:image:alt'][content=?]", I18n.t("layouts.og_image_alt")
    assert_select "meta[name='twitter:card'][content=?]", "summary_large_image"
    assert_select "meta[name='twitter:title'][content=?]", title
    assert_select "meta[name='twitter:description'][content=?]", I18n.t("home.index.meta_description")

    # 素の単語一覧と検索フォームはトップと異なる固有の description を持つ
    get words_path
    assert_select "meta[name=description][content=?]", I18n.t("words.index.description")

    get search_path
    assert_select "meta[name=description][content=?]", I18n.t("searches.description")

    # canonical はクエリパラメータを含めず現在のパスのみを使う(既定の挙動)
    # /words は Issue 17 で canonical を正規化上書きするため、上書きしない /search で既定挙動を確認する。
    get search_path(q: "テスト", genre_id: 1)
    assert_response :success
    assert_select "link[rel=canonical][href=?]", "#{CANONICAL_HOST}/search"
  end

  test "単語詳細の description・og:type・canonical・og:image" do
    word = words(:abc_murder)
    get word_path(word)
    assert_response :success

    lead = "「ABC殺人事件」は、読み「さつじんじけん」（7文字・7モーラ）の日本語の長い言葉。" \
           "ジャンルは 文学 › 日本文学 › 小説。人を殺す事件"
    assert_select "meta[name=description][content=?]", lead
    assert_select "meta[property='og:description'][content=?]", lead
    assert_select "meta[property='og:type'][content=?]", "article"
    assert_select "link[rel=canonical][href=?]", "#{CANONICAL_HOST}/words/#{word.id}"
    assert_select "meta[property='og:url'][content=?]", "#{CANONICAL_HOST}/words/#{word.id}"

    # 単語詳細の og:image は語ごとの共有カード(版つき)で、焼けない環境では既定のカードのまま
    word = words(:abc_murder)
    stub_method(ShareCardRenderer, :available?, -> { true }) { get word_path(word) }
    assert_select "meta[property='og:image'][content=?]",
                  "#{CANONICAL_HOST}/words/#{word.id}/share_card.png?v=#{WordShareCard.new(word).digest}"
    assert_select "meta[property='og:image:alt'][content=?]",
                  I18n.t("words.share_card.alt", surface: word.surface, reading: word_senses(:murder).reading)

    stub_method(ShareCardRenderer, :available?, -> { false }) { get word_path(word) }
    assert_select "meta[property='og:image'][content=?]", "#{CANONICAL_HOST}/og-default.png"
    assert_select "meta[property='og:image:alt'][content=?]", I18n.t("layouts.og_image_alt")
  end
end
