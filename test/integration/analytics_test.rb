require "test_helper"

# GA4 / サーチコンソール確認タグ(Issue 19)。いずれも環境変数で駆動し、未設定なら一切出力しない。
class AnalyticsTest < ActionDispatch::IntegrationTest
  test "GA4 タグと所有権確認メタは環境変数があるときだけ出し、GA4 タグはログイン中(管理画面を含む)には出さない" do
    get root_path
    assert_response :success
    assert_select "script[src*='googletagmanager.com']", count: 0
    assert_no_match "send_page_view", response.body
    assert_select "meta[name='google-site-verification']", count: 0
    assert_select "meta[name='msvalidate.01']", count: 0

    # 環境変数があれば gtag を Turbo 対応で読み込み、所有権確認メタを出力する
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
      # タグの有無が変わる遷移(ログイン・ログアウト)は Turbo にフルロードさせる(リスナーを残さない)
      assert_select "script[src*='googletagmanager.com'][data-turbo-track=reload]", count: 1
      assert_select "script[data-turbo-track=reload]:not([src])", text: /send_page_view: false/, count: 1

      # ログイン中は、管理画面でも公開側でも GA4 タグを出さない(所有権確認メタは誰が見ても同じ)
      sign_in_as(admins(:one))
      [ admin_root_path, root_path ].each do |path|
        get path
        assert_response :success
        assert_select "script[src*='googletagmanager.com']", { count: 0 }, "#{path} に GA4 タグが出ている"
        assert_no_match "send_page_view", response.body
        assert_select "meta[name='google-site-verification'][content=?]", "goog-abc"
      end
    end
  end
end
