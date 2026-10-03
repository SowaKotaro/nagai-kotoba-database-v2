require "test_helper"

# sitemap.xml(Issue 15)。条件付きGET と版の畳み方は PublishedWordsDigestTest で見る。
class SitemapsControllerTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "sitemap.xml は誰でも取得でき、静的ページと公開語だけを本番ホストの絶対URLで並べる" do
    get "/sitemap.xml"
    assert_response :success
    assert_match %r{application/xml|text/xml}, response.media_type
    assert_match "http://www.sitemaps.org/schemas/sitemap/0.9", response.body

    %w[/ /words /genres /browse /stats /about /privacy].each do |path|
      assert_includes response.body, "<loc>#{HOST}#{path}</loc>"
    end
    assert_includes response.body, "<loc>#{HOST}/words/#{words(:abc_murder).id}</loc>"
    assert_match %r{<lastmod>\d{4}-\d{2}-\d{2}}, response.body
    # 未注釈の語は含めない
    assert_not_includes response.body, "/words/#{words(:pending_haruhi).id}<"
  end

  test "sitemap.xml の <loc> は、静的ページ 8 件と公開語の詳細だけ(この順)" do
    get "/sitemap.xml"
    locs = Nokogiri::XML(response.body).remove_namespaces!.css("url > loc").map(&:text)

    static = %w[/ /words /genres /browse /rankings /stats /about /privacy].map { |path| "#{HOST}#{path}" }
    published = Word.annotated.order(:id).map { |word| "#{HOST}/words/#{word.id}" }
    assert_equal static + published, locs
  end
end
