require "application_system_test_case"

# 管理者ログインの実機スモーク(ヘッドレス Chrome が動くことの確認を兼ねる)。
class AdminLoginTest < ApplicationSystemTestCase
  test "管理者がログインするとダッシュボードに共通ナビが出る" do
    system_sign_in
    visit admin_root_path

    assert_selector "h1", text: "管理コンソール"
    # 共通サブナビ(Issue 35)と現在地
    assert_selector ".admin-nav a[aria-current=page]", text: "ダッシュボード"
  end
end
