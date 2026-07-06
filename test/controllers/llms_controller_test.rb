require "test_helper"

class LlmsControllerTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "llms.txt は未認証で取得でき text/plain を返す" do
    get "/llms.txt"
    assert_response :success
    assert_equal "text/plain", response.media_type
  end

  test "llms.txt にサイト概要・主要ページ・ライセンスが載る" do
    get "/llms.txt"
    body = response.body

    assert_includes body, I18n.t("layouts.brand")
    assert_includes body, "10文字以上"                       # 収録基準
    assert_includes body, "#{HOST}/words"
    assert_includes body, "#{HOST}/about"
    assert_includes body, "#{HOST}/sitemap.xml"
    assert_includes body, "CC BY 4.0"                        # ライセンス
    assert_includes body, "#{HOST}"                          # クレジットの URL
  end

  test "llms ルートは /llms.txt を生成する" do
    assert_equal "/llms.txt", llms_path
  end
end
