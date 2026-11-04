require "test_helper"

# サイト情報(About。Issue 20)とプライバシーポリシー(Issue 42)。
class PagesControllerTest < ActionDispatch::IntegrationTest
  test "About とプライバシーポリシーは誰でも見られ、必要な事項と連絡先を載せる" do
    get about_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("layouts.brand")
    assert_select "meta[name=robots]", count: 0
    assert_select "meta[name=description][content=?]", I18n.t("pages.about.description")

    # 章は 1 つずつ札に収める(収録基準と精査方針の章がある)。よくある質問は問答の行に積む
    assert_select ".panel .panel__title", text: I18n.t("pages.about.criteria_title")
    assert_select ".panel .panel__title", text: I18n.t("pages.about.curation_title")
    assert_select ".faq-list__question", count: I18n.t("pages.about.faq_items").size
    # CC BY 4.0 のライセンス表記とリンク、連絡先メール、プライバシーポリシーへの導線
    assert_select "a[rel~=license][href=?]", "https://creativecommons.org/licenses/by/4.0/deed.ja"
    assert_select ".prose__credit", text: /長い言葉のデータベース .https:\/\/nagai-kotoba-database\.jp./
    assert_select "a[href=?]", "mailto:#{I18n.t('pages.about.contact_email')}"
    assert_select ".prose a[href=?]", privacy_path

    # 収録語数はページの頭のレールに立て、同じ数を本文でも文で言う
    count = Word.annotated.count
    assert_select ".page-header__count", text: "#{ActiveSupport::NumberHelper.number_to_delimited(count)}#{I18n.t('pages.about.count_unit')}"
    assert_select ".prose", text: /現在 #{count} 語を収録しています。/

    # プライバシーポリシーは誰でも見られ、外部送信の公表事項(送信先・情報・目的)と連絡先を載せる
    get privacy_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("pages.privacy.title")
    assert_select "meta[name=description][content=?]", I18n.t("pages.privacy.description")

    # 外部送信規律の3点セット(名前と値の行)
    assert_select ".fact-list dd", text: I18n.t("pages.privacy.analytics_destination")
    assert_select ".fact-list dt", text: I18n.t("pages.privacy.analytics_data_label")
    assert_select ".fact-list dt", text: I18n.t("pages.privacy.analytics_purpose_label")
    # Google のポリシーへのリンクとオプトアウト
    assert_select "a[href=?]", "https://policies.google.com/privacy"
    assert_select "a[href=?]", "https://tools.google.com/dlpage/gaoptout"
    # Cookie・アクセスログ・連絡先
    assert_select ".prose", text: /Cookie/
    assert_select ".prose", text: /アクセスログ/
    assert_select "a[href=?]", "mailto:#{I18n.t('pages.about.contact_email')}"
  end

  # 収録語数は毎リクエスト COUNT を打つほどの値ではないので 1 日キャッシュする。
  test "About の収録語数は 1 日は数え直さず、期限が切れたら数え直す" do
    with_rails_cache do
      travel_to Time.zone.local(2026, 10, 4, 12, 0)
      get about_path
      assert_select ".prose", text: /現在 2 語を収録しています。/

      create_published_word(surface: "About の語数の見本", reading: "アバウトノゴスウノミホン")
      travel 1.day - 1.minute
      get about_path
      assert_select ".prose", text: /現在 2 語を収録しています。/

      travel 2.minutes
      get about_path
      assert_select ".prose", text: /現在 3 語を収録しています。/
    end
  end
end
