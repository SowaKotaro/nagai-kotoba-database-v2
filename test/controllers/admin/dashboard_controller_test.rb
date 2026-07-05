require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "未認証だとログインへリダイレクト" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "認証済みなら収録状況と各作業への導線を表示する" do
    sign_in_as(Admin.take)
    get admin_root_path
    assert_response :success

    # 統計(総数・注釈済み・未注釈)
    assert_select ".stats-grid__item", minimum: 3
    # 登録・アノテーション・管理への入口カード
    assert_select "a.admin-card[href=?]", new_admin_word_path
    assert_select "a.admin-card[href=?]", admin_annotations_path
    assert_select "a.admin-card[href=?]", admin_words_path
    # 未注釈の残数を表示する
    assert_select "a.admin-card[href=?]", admin_annotations_path,
      text: /#{Word.unannotated.count}/
  end
end
