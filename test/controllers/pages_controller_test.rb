require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "About は未認証で閲覧でき index 可能(noindex を出さない)" do
    get about_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("layouts.brand")
    assert_select "meta[name=robots]", count: 0
    assert_select "meta[name=description][content=?]", I18n.t("pages.about.description")
  end

  test "About に収録基準・精査・利用条件(CC BY 4.0)・連絡先が載る" do
    get about_path
    # 収録基準(読み10文字以上)と精査方針
    assert_select ".prose", text: /収録の基準/
    assert_select ".prose", text: /データの精査/
    # CC BY 4.0 のライセンス表記とリンク
    assert_select "a[rel~=license][href=?]", "https://creativecommons.org/licenses/by/4.0/deed.ja"
    assert_select ".prose__credit", text: /長い言葉のデータベース .https:\/\/nagai-kotoba-database\.jp./
    # 連絡先メール
    assert_select "a[href=?]", "mailto:specialnamahamu@gmail.com"
  end

  test "About はフッターから恒久リンクされている" do
    get root_path
    assert_select "footer a[href=?]", about_path, text: I18n.t("layouts.nav.about")
  end

  test "sitemap に About が含まれる" do
    get "/sitemap.xml"
    assert_includes response.body, "<loc>https://nagai-kotoba-database.jp/about</loc>"
  end
end
