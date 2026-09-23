require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# ジャンルの段階表示ピッカー(genre-picker)が使う JSON API: 子ジャンルの取得と、その場での追加。
# その場追加の共通処理(InlineMasterCreatable)の空白・照合順序の衝突の扱いはここで押さえ、
# 単純マスタ3種のエンドポイントは Admin::InlineMasterCreationTest で見る。
class Admin::GenresControllerTest < ActionDispatch::IntegrationTest
  test "指定した親の子ジャンルを JSON で返し、親未指定なら空配列を返す" do
    sign_in_as(Admin.take)
    get children_admin_genres_path(parent_id: genres(:large_literature).id)
    assert_response :success
    assert_equal [ { "id" => genres(:medium_japanese).id, "name" => genres(:medium_japanese).name } ],
                 JSON.parse(response.body)

    get children_admin_genres_path
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  # --- その場追加(コンソールから画面遷移せずにジャンルを作る) ---

  test "親の下に小分類を作り、同じ親の下に同名が既にあれば作らずに既存を返す" do
    sign_in_as(Admin.take)
    assert_difference -> { Genre.count } => 1 do
      post admin_genres_path, params: { name: "新しい小分類", parent_id: genres(:medium_japanese).id }, as: :json
    end
    created = Genre.find(response.parsed_body["id"])
    assert created.small?
    assert_equal genres(:medium_japanese), created.parent

    assert_no_difference -> { Genre.count } do
      post admin_genres_path, params: { name: genres(:small_novel).name, parent_id: genres(:medium_japanese).id }, as: :json
    end
    assert_response :success
    assert_equal genres(:small_novel).id, response.parsed_body["id"]
    assert response.parsed_body["existing"]
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

  test "前後の空白(全角を含む)は落として作り、空白だけの名前はエラーの理由を返す" do
    sign_in_as(Admin.take)
    post admin_genres_path, params: { name: "　 SF 　", parent_id: genres(:medium_japanese).id }, as: :json
    assert_response :success
    assert_equal "SF", response.parsed_body["name"]

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
end
