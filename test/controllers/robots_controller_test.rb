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

  # シード付き URL も Disallow しない。既知の分は「noindex + canonical は /words」を
  # 宣言済みで、ブロックすると Google がその訂正(canonical を自身へ向けた修正)を
  # 読めなくなり、サイトのハブへ noindex が伝播したまま凍結されるため。
  # 生成元は絶ってあるので、新しいシード付き URL が増えることはない。
  test "シャッフルのシード付き URL は Disallow しない(noindex と canonical を読ませる)" do
    get robots_path
    # 撤去の経緯をコメントに残してあり本文には文字列として現れるので、
    # 実際に効くディレクティブ行(コメント以外)だけを見る。
    assert_not_includes robots_directives, "Disallow: /*seed="
  end

  private

  # コメント・空行を除いた、クローラが実際に読むディレクティブ行。
  def robots_directives
    response.body.lines.map(&:strip).grep_v(/\A(#|\z)/)
  end
end
