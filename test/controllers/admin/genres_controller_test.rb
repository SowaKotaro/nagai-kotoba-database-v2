require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::GenresControllerTest < ActionDispatch::IntegrationTest
  test "未認証だと子ジャンルを取得できない" do
    get children_admin_genres_path(parent_id: genres(:large_literature).id)
    assert_redirected_to new_session_path
  end

  test "指定した親の子ジャンルを JSON で返す" do
    sign_in_as(Admin.take)
    get children_admin_genres_path(parent_id: genres(:large_literature).id)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ { "id" => genres(:medium_japanese).id, "name" => genres(:medium_japanese).name } ], body
  end

  test "親未指定なら空配列を返す" do
    sign_in_as(Admin.take)
    get children_admin_genres_path

    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end
end
