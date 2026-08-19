require "test_helper"

# robots.txt(動的配信)のテスト。Sitemap 行が canonical_host と連動すること。
class RobotsControllerTest < ActionDispatch::IntegrationTest
  test "robots.txt は未認証で取得でき text/plain で返る" do
    get robots_path
    assert_response :success
    assert_equal "text/plain", response.media_type
  end

  test "管理・認証を Disallow し sitemap の絶対URLを案内する" do
    get robots_path
    assert_includes response.body, "Disallow: /admin"
    assert_includes response.body, "Disallow: /session"
    # ホストは config.x.canonical_host(テストでは既定値)に連動する
    host = Rails.application.config.x.canonical_host
    assert_includes response.body, "Sitemap: #{host}/sitemap.xml"
  end

  test "検索フォームは Disallow しない(noindex を読ませるためクロールは許可する)" do
    get robots_path
    assert_not_includes response.body, "Disallow: /search"
  end

  # シャッフルのシード付き URL は無限に増やせてしまうので、クロールごと止める。
  # /search と違い元から実在しないページなので、noindex を読ませる必要がない。
  test "シャッフルのシード付き URL は Disallow する" do
    get robots_path
    assert_includes response.body, "Disallow: /*seed="
  end
end
