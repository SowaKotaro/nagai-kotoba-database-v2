require "test_helper"

class SitemapsControllerTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "sitemap.xml は未認証で取得でき XML を返す" do
    get "/sitemap.xml"
    assert_response :success
    assert_match %r{application/xml|text/xml}, response.media_type
    assert_match "http://www.sitemaps.org/schemas/sitemap/0.9", response.body
  end

  test "sitemap に静的ページと公開(注釈済み)単語が本番ホストの絶対URLで並ぶ" do
    get "/sitemap.xml"

    assert_includes response.body, "<loc>#{HOST}/</loc>"
    assert_includes response.body, "<loc>#{HOST}/words</loc>"
    assert_includes response.body, "<loc>#{HOST}/words/#{words(:abc_murder).id}</loc>"
    # 更新日時が lastmod として入る
    assert_select_xml_has_lastmod
  end

  test "未注釈の語は sitemap に含めない" do
    get "/sitemap.xml"
    assert_not_includes response.body, "/words/#{words(:pending_haruhi).id}<"
    assert_not_includes response.body, "/words/#{words(:pending_haruhi).id}</loc>"
  end

  test "sitemap ルートは /sitemap.xml を生成する" do
    assert_equal "/sitemap.xml", sitemap_path
  end

  private

  def assert_select_xml_has_lastmod
    assert_match %r{<lastmod>\d{4}-\d{2}-\d{2}}, response.body
  end
end
