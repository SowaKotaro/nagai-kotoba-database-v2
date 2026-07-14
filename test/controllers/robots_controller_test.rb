require "test_helper"

# robots.txt(動的配信)のテスト。Sitemap 行が canonical_host と連動すること。
class RobotsControllerTest < ActionDispatch::IntegrationTest
  test "robots.txt は未認証で取得でき text/plain で返る" do
    get robots_path
    assert_response :success
    assert_equal "text/plain", response.media_type
  end

  test "管理・認証・検索フォームを Disallow し sitemap の絶対URLを案内する" do
    get robots_path
    assert_includes response.body, "Disallow: /admin"
    assert_includes response.body, "Disallow: /session"
    assert_includes response.body, "Disallow: /search"
    # ホストは config.x.canonical_host(テストでは既定値)に連動する
    host = Rails.application.config.x.canonical_host
    assert_includes response.body, "Sitemap: #{host}/sitemap.xml"
  end
end
