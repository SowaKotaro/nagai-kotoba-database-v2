require "test_helper"

# robots.txt(動的配信)。Sitemap 行を canonical_host と連動させ、noindex を読ませたい面はブロックしない。
class RobotsControllerTest < ActionDispatch::IntegrationTest
  test "robots.txt は誰でも取得でき、管理・認証を Disallow して sitemap の絶対URLを案内する" do
    get robots_path
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes robots_directives, "Disallow: /admin"
    assert_includes robots_directives, "Disallow: /session"
    # ホストは config.x.canonical_host に連動する。テストが前提にする既定値(CANONICAL_HOST)と同じであることも
    # ここで確かめる(環境変数 CANONICAL_HOST を設定した環境では、ここで先に分かる)
    assert_equal CANONICAL_HOST, Rails.application.config.x.canonical_host
    assert_includes robots_directives, "Sitemap: #{CANONICAL_HOST}/sitemap.xml"
  end

  # 検索フォームは noindex を読ませるためにクロールを許す。シード付き URL も、既知の分は
  # 「noindex + canonical は /words」を宣言済みで、ブロックすると Google がその訂正(canonical を
  # 自身へ向けた修正)を読めなくなり、サイトのハブへ noindex が伝播したまま凍結されるため許す。
  # 生成元は絶ってあるので、新しいシード付き URL が増えることはない。
  test "検索フォームとシャッフルのシード付き URL は Disallow しない(noindex と canonical を読ませる)" do
    get robots_path
    assert_not_includes robots_directives, "Disallow: /search"
    assert_not_includes robots_directives, "Disallow: /*seed="
  end

  private

  # コメント・空行を除いた、クローラが実際に読むディレクティブ行
  # (撤去の経緯をコメントに残してあり、本文には文字列として現れるため)。
  def robots_directives
    response.body.lines.map(&:strip).grep_v(/\A(#|\z)/)
  end
end
