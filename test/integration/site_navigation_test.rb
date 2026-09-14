require "test_helper"

# 公開ページ共通のヘッダー・フッター。主要ページへの恒久リンクを外さない
# (クロール導線でもあるので、sitemap に載せるだけでなく全ページから辿れるようにしている)。
class SiteNavigationTest < ActionDispatch::IntegrationTest
  test "ヘッダーとフッターから主要ページへ恒久リンクされている" do
    get root_path
    assert_response :success

    # ヘッダーは統計と、「検索」プルダウンの中のジャンル・索引
    assert_select "header a[href=?]", stats_path
    assert_select "header a[href=?]", genres_path, text: I18n.t("layouts.nav.genres")
    assert_select "header a[href=?]", browse_path, text: I18n.t("layouts.nav.browse")

    assert_select "footer a[href=?]", genres_path, text: I18n.t("layouts.nav.genres")
    assert_select "footer a[href=?]", browse_path, text: I18n.t("layouts.nav.browse")
    assert_select "footer a[href=?]", stats_path
    assert_select "footer a[href=?]", about_path, text: I18n.t("layouts.nav.about")
    assert_select "footer a[href=?]", privacy_path, text: I18n.t("layouts.nav.privacy")
  end
end
