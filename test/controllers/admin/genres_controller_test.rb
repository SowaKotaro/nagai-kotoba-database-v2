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

  # --- その場追加(コンソールから画面遷移せずにジャンルを作る) ---

  test "同じ親の下に同名が既にあれば、作らずに既存を返す" do
    sign_in_as(Admin.take)
    assert_no_difference -> { Genre.count } do
      post admin_genres_path, params: { name: genres(:small_novel).name, parent_id: genres(:medium_japanese).id }, as: :json
    end

    assert_response :success
    assert_equal genres(:small_novel).id, response.parsed_body["id"]
    assert response.parsed_body["existing"]
  end

  test "前後の空白(全角を含む)は落として作る" do
    sign_in_as(Admin.take)
    post admin_genres_path, params: { name: "　 SF 　", parent_id: genres(:medium_japanese).id }, as: :json

    assert_response :success
    assert_equal "SF", response.parsed_body["name"]
  end

  test "空白だけの名前はエラーの理由を返す" do
    sign_in_as(Admin.take)
    assert_no_difference -> { Genre.count } do
      post admin_genres_path, params: { name: "　 ", parent_id: genres(:medium_japanese).id }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ I18n.t("admin.inline_add.blank_name") ], response.parsed_body["errors"]
  end

  # 照合順序 utf8mb4_0900_ai_ci は「ハ」と「バ」やひらがな/カタカナを同一視するため、
  # 見た目の違う名前でもユニーク制約に当たる。黙って別のジャンルを選ばせず理由を返す。
  test "濁点違いなど照合順序で衝突する名前は、既存を示すエラーを返す" do
    sign_in_as(Admin.take)
    existing = Genre.create!(name: "ハンド", parent: genres(:medium_japanese), level: :small)

    assert_no_difference -> { Genre.count } do
      post admin_genres_path, params: { name: "バンド", parent_id: genres(:medium_japanese).id }, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"].first, existing.name
  end

  test "親が違えば同名のジャンルを作れる" do
    sign_in_as(Admin.take)
    other = Genre.create!(name: "外国文学", parent: genres(:large_literature), level: :medium)

    assert_difference -> { Genre.count } => 1 do
      post admin_genres_path, params: { name: genres(:small_novel).name, parent_id: other.id }, as: :json
    end

    assert_response :success
    assert_not_equal genres(:small_novel).id, response.parsed_body["id"]
  end
end
