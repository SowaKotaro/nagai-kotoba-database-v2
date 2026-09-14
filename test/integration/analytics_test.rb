require "test_helper"

# GA4 / サーチコンソール確認タグ(Issue 19)。いずれも環境変数で駆動し、未設定なら一切出力しない。
class AnalyticsTest < ActionDispatch::IntegrationTest
  test "環境変数が無ければ GA4 タグも所有権確認メタも出力しない" do
    get root_path
    assert_response :success
    assert_select "script[src*='googletagmanager.com']", count: 0
    assert_no_match "send_page_view", response.body
    assert_select "meta[name='google-site-verification']", count: 0
    assert_select "meta[name='msvalidate.01']", count: 0
  end

  test "環境変数があれば gtag を Turbo 対応で読み込み、所有権確認メタを出力する" do
    with_env("GA4_MEASUREMENT_ID" => "G-TEST12345",
             "GOOGLE_SITE_VERIFICATION" => "goog-abc", "BING_SITE_VERIFICATION" => "bing-xyz") do
      get root_path
      assert_response :success
      assert_select "script[src=?]", "https://www.googletagmanager.com/gtag/js?id=G-TEST12345"
      # 既定の page_view は止め、turbo:load ごとに送る
      assert_match "send_page_view: false", response.body
      assert_match "turbo:load", response.body
      assert_match "G-TEST12345", response.body
      assert_select "meta[name='google-site-verification'][content=?]", "goog-abc"
      assert_select "meta[name='msvalidate.01'][content=?]", "bing-xyz"
    end
  end

  private

  def with_env(vars)
    original = vars.keys.index_with { |key| ENV.fetch(key, :absent) }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value == :absent ? ENV.delete(key) : ENV[key] = value }
  end
end
