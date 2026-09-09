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

  test "About は図・イラストを一切持たない(文章だけで組む)" do
    get about_path

    # 線画(円環・放射図)も写真プレースホルダも置かない(docs/design.md §5.7。オーナー判断)
    assert_select ".ring-art", count: 0
    assert_select ".image-slot", count: 0
    assert_select "svg[role=img]", count: 0
    # ページ内もくじも持たない
    assert_select ".page-toc", count: 0
  end

  test "About の標識は2行目に収録語数を持ち、同じ数を日本語でも出す" do
    get about_path
    count = Word.annotated.count

    assert_select ".label-en", text: I18n.t("labels.en.entries", count: ActiveSupport::NumberHelper.number_to_delimited(count))
    assert_select ".prose", text: /現在 #{count} 語を収録しています。/
  end

  test "About はフッターから恒久リンクされている" do
    get root_path
    assert_select "footer a[href=?]", about_path, text: I18n.t("layouts.nav.about")
  end

  test "sitemap に About が含まれる" do
    get "/sitemap.xml"
    assert_includes response.body, "<loc>https://nagai-kotoba-database.jp/about</loc>"
  end

  # --- プライバシーポリシー(外部送信情報の公表。Issue 42) ---
  test "プライバシーポリシーは未認証で閲覧できる" do
    get privacy_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("pages.privacy.title")
    assert_select "meta[name=description][content=?]", I18n.t("pages.privacy.description")
  end

  test "プライバシーポリシーに外部送信の公表事項(送信先・情報・目的)と連絡先が載る" do
    get privacy_path
    # 外部送信規律の3点セット
    assert_select ".prose", text: /Google LLC/
    assert_select ".prose", text: /送信される情報/
    assert_select ".prose", text: /利用目的/
    # Google のポリシーへのリンクとオプトアウト
    assert_select "a[href=?]", "https://policies.google.com/privacy"
    assert_select "a[href=?]", "https://tools.google.com/dlpage/gaoptout"
    # Cookie・アクセスログ・連絡先
    assert_select ".prose", text: /Cookie/
    assert_select ".prose", text: /アクセスログ/
    assert_select "a[href=?]", "mailto:#{I18n.t('pages.about.contact_email')}"
  end

  test "プライバシーポリシーはフッター・About・llms.txt・sitemap から参照される" do
    get root_path
    assert_select "footer a[href=?]", privacy_path, text: I18n.t("layouts.nav.privacy")

    get about_path
    assert_select ".prose a[href=?]", privacy_path

    get "/llms.txt"
    assert_includes response.body, "https://nagai-kotoba-database.jp/privacy"

    get "/sitemap.xml"
    assert_includes response.body, "<loc>https://nagai-kotoba-database.jp/privacy</loc>"
  end
end
