require "test_helper"

# 管理画面の共通サブナビ(Issue 35)。全管理ページに常設し、現在地を aria-current で示す。
class AdminNavTest < ActionDispatch::IntegrationTest
  test "管理各画面に共通ナビが出て、現在地に aria-current が付く" do
    sign_in_as(Admin.take)

    # ダッシュボード
    get admin_root_path
    assert_select ".admin-nav" do
      assert_select "a[aria-current=page][href=?]", admin_root_path
      assert_select "a[href=?]", new_admin_word_path
      assert_select "a[href=?]", admin_annotations_path
      assert_select "a[href=?]", admin_words_path
      assert_select "a[href=?]", root_path
    end

    # 登録フロー(admin/words だが「単語を登録」が現在地になる)
    get new_admin_word_path
    assert_select ".admin-nav a[aria-current=page][href=?]", new_admin_word_path

    # 一覧(同じ admin/words でも「単語の管理」が現在地になる)
    get admin_words_path
    assert_select ".admin-nav a[aria-current=page][href=?]", admin_words_path

    # アノテーション・コンソール(入口は提案キュー優先で多段リダイレクトになる。Issue 69)
    get admin_annotations_path
    follow_redirect! while response.redirect?
    assert_select ".admin-nav a[aria-current=page][href=?]", admin_annotations_path
  end

  test "公開ページには共通ナビを出さない" do
    get root_path
    assert_select ".admin-nav", count: 0

    # ログイン済みでも公開側には出さない
    sign_in_as(Admin.take)
    get words_path
    assert_select ".admin-nav", count: 0
  end
end
