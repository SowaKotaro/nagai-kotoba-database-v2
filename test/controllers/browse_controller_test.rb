require "test_helper"

class BrowseControllerTest < ActionDispatch::IntegrationTest
  test "索引は未認証で閲覧でき index 可能" do
    get browse_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("browse.index.title")
    assert_select "meta[name=robots]", count: 0
  end

  test "50音・文字数から単語一覧の絞り込みへリンクする" do
    get browse_path
    # カ(curry の読み カレー)→ 先頭文字の絞り込み
    assert_select "a.kana-cell--link[href=?]", words_path(first_char: "カ")
    # 読みの文字数 3(カレー)・7(さつじんじけん)→ 文字数の絞り込み
    assert_select "a.browse-length[href=?]", words_path(reading_length: 3)
    assert_select "a.browse-length[href=?]", words_path(reading_length: 7)
  end

  test "公開語義が無い先頭文字はリンクにせず muted 表示にする" do
    get browse_path
    assert_select "a.kana-cell--link[href=?]", words_path(first_char: "ヲ"), count: 0
    assert_select ".kana-cell--muted", minimum: 1
  end

  test "索引はヘッダー/フッター/sitemap からリンクされる" do
    get root_path
    assert_select "header a[href=?]", browse_path, text: I18n.t("layouts.nav.browse")
    assert_select "footer a[href=?]", browse_path, text: I18n.t("layouts.nav.browse")

    get "/sitemap.xml"
    assert_includes response.body, "<loc>https://nagai-kotoba-database.jp/browse</loc>"
  end
end
