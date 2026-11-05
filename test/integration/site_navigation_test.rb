require "test_helper"

# 公開ページ共通のヘッダー・フッター。主要ページへの恒久リンクを外さない
# (クロール導線でもあるので、sitemap に載せるだけでなく全ページから辿れるようにしている)。
class SiteNavigationTest < ActionDispatch::IntegrationTest
  test "ヘッダーとフッターから主要ページへリンクし、本文へのスキップリンクがある" do
    get root_path
    assert_response :success

    # ヘッダーは統計と、「検索」プルダウンの中の、詳細検索から切り出した探し方(ジャンル・エンティティ・言語学的特徴・索引)。
    # フッターの「さがす」にも同じものを並べる
    assert_select "header a[href=?]", stats_path
    search_pages = { genres_path => "genres", entity_types_path => "entity_types",
                     linguistic_features_path => "linguistic_features", browse_path => "browse" }
    search_pages.each do |path, key|
      assert_select "header a[href=?]", path, text: I18n.t("layouts.nav.#{key}")
      assert_select "footer a[href=?]", path, text: I18n.t("layouts.nav.#{key}")
    end
    assert_select "footer a[href=?]", stats_path
    assert_select "footer a[href=?]", about_path, text: I18n.t("layouts.nav.about")
    assert_select "footer a[href=?]", privacy_path, text: I18n.t("layouts.nav.privacy")

    # サイト名は 1 字ずつ包んで伸ばす(motion.css の 3)。つないだ字は名前のままで、伸ばし棒は 1 字目の data 属性だけに持つ
    # (本文の文字に混ぜない)。読み上げは aria-label で名前ひとつにまとめる
    brand = I18n.t("layouts.brand")
    assert_select "header a.site-brand[href=?][aria-label=?]", root_path, brand do |links|
      assert_equal brand, links.first.text
      assert_equal brand.length, css_select(links.first, ".site-brand__char").size
      assert_select ".site-brand__char:first-child[data-stretch-mark=?]", I18n.t("layouts.brand_stretch_mark")
      assert_select ".site-brand__char[data-stretch-mark]", 1
    end

    # ヘッダーより前に本文へのスキップリンクがあり、飛び先の main がフォーカスを受けられる
    get words_path

    assert_select "body > a.skip-link:first-child[href='#main']", text: I18n.t("layouts.skip_to_main")
    assert_select "main#main[tabindex='-1']"
  end
end
