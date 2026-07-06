require "test_helper"

# GA4 / サーチコンソール確認タグ(Issue 19)の結合テスト。
# いずれも環境変数で駆動し、未設定なら一切出力しないことを担保する。
class AnalyticsTest < ActionDispatch::IntegrationTest
  test "測定IDが未設定なら GA4 タグを一切出力しない" do
    get root_path
    assert_response :success
    assert_select "script[src*='googletagmanager.com']", count: 0
    assert_no_match "send_page_view", response.body
  end

  test "GA4_MEASUREMENT_ID があれば gtag を Turbo 対応で読み込む" do
    with_env("GA4_MEASUREMENT_ID" => "G-TEST12345") do
      get root_path
      assert_response :success
      assert_select "script[src=?]", "https://www.googletagmanager.com/gtag/js?id=G-TEST12345"
      # 既定の page_view は止め、turbo:load ごとに送る
      assert_match "send_page_view: false", response.body
      assert_match "turbo:load", response.body
      assert_match "G-TEST12345", response.body
    end
  end

  test "所有権確認メタは環境変数があるときだけ出力する" do
    get root_path
    assert_select "meta[name='google-site-verification']", count: 0
    assert_select "meta[name='msvalidate.01']", count: 0

    with_env("GOOGLE_SITE_VERIFICATION" => "goog-abc", "BING_SITE_VERIFICATION" => "bing-xyz") do
      get root_path
      assert_select "meta[name='google-site-verification'][content=?]", "goog-abc"
      assert_select "meta[name='msvalidate.01'][content=?]", "bing-xyz"
    end
  end

  private

  def with_env(vars)
    original = vars.transform_values { |_| :absent }
    vars.each_key { |k| original[k] = ENV.key?(k) ? ENV[k] : :absent }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v == :absent ? ENV.delete(k) : ENV[k] = v }
  end
end
