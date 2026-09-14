require "test_helper"

# サイト情報(About。Issue 20)とプライバシーポリシー(Issue 42)。
class PagesControllerTest < ActionDispatch::IntegrationTest
  test "About は誰でも見られ(index 可)、収録基準・精査・利用条件・連絡先と収録語数を載せる" do
    get about_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("layouts.brand")
    assert_select "meta[name=robots]", count: 0
    assert_select "meta[name=description][content=?]", I18n.t("pages.about.description")

    # 収録基準(読み10文字以上)と精査方針
    assert_select ".prose", text: /収録の基準/
    assert_select ".prose", text: /データの精査/
    # CC BY 4.0 のライセンス表記とリンク、連絡先メール、プライバシーポリシーへの導線
    assert_select "a[rel~=license][href=?]", "https://creativecommons.org/licenses/by/4.0/deed.ja"
    assert_select ".prose__credit", text: /長い言葉のデータベース .https:\/\/nagai-kotoba-database\.jp./
    assert_select "a[href=?]", "mailto:#{I18n.t('pages.about.contact_email')}"
    assert_select ".prose a[href=?]", privacy_path

    # 標識は2行目に収録語数を持ち、同じ数を日本語でも出す
    count = Word.annotated.count
    assert_select ".label-en", text: I18n.t("labels.en.entries", count: ActiveSupport::NumberHelper.number_to_delimited(count))
    assert_select ".prose", text: /現在 #{count} 語を収録しています。/
  end

  # 線画(円環・放射図)も写真プレースホルダも、ページ内もくじも置かない(docs/design.md §5.7。オーナー判断)
  test "About は図・イラスト・もくじを持たず、文章だけで組む" do
    get about_path
    assert_select ".ring-art", count: 0
    assert_select ".image-slot", count: 0
    assert_select "svg[role=img]", count: 0
    assert_select ".page-toc", count: 0
  end

  test "プライバシーポリシーは誰でも見られ、外部送信の公表事項(送信先・情報・目的)と連絡先を載せる" do
    get privacy_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("pages.privacy.title")
    assert_select "meta[name=description][content=?]", I18n.t("pages.privacy.description")

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
end
