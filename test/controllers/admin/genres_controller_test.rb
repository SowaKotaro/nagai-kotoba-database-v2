require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# ジャンルの段階表示ピッカー(genre-picker)が使う JSON API: 子ジャンルの取得と、その場での追加。
# その場追加の共通処理(InlineMasterCreatable)の空白・照合順序の衝突の扱いはここで押さえ、
# 単純マスタ3種のエンドポイントは Admin::InlineMasterCreationTest で見る。
class Admin::GenresControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(admins(:one)) }

  test "子ジャンルの JSON と、親の下への小分類の作成(同名は既存を返し、親が違えば作れる)" do
    get children_admin_genres_path(parent_id: genres(:large_literature).id)
    assert_response :success
    assert_equal [ { "id" => genres(:medium_japanese).id, "name" => genres(:medium_japanese).name } ],
                 JSON.parse(response.body)

    get children_admin_genres_path
    assert_response :success
    assert_equal [], JSON.parse(response.body)

    # 親の下に小分類を作り、同じ親の下に同名が既にあれば作らずに既存を返す
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

    # 親が違えば同名のジャンルを作れる
    other = Genre.create!(name: "外国文学", parent: genres(:large_literature), level: :medium)

    assert_difference -> { Genre.count } => 1 do
      post admin_genres_path, params: { name: genres(:small_novel).name, parent_id: other.id }, as: :json
    end

    assert_response :success
    assert_not_equal genres(:small_novel).id, response.parsed_body["id"]
  end

  # --- その場追加(コンソールから画面遷移せずにジャンルを作る) ---

  test "名前の空白は落とし、空白だけ・照合順序で衝突する名前はエラーの理由を返す" do
    post admin_genres_path, params: { name: "　 SF 　", parent_id: genres(:medium_japanese).id }, as: :json
    assert_response :success
    assert_equal "SF", response.parsed_body["name"]

    assert_no_difference -> { Genre.count } do
      post admin_genres_path, params: { name: "　 ", parent_id: genres(:medium_japanese).id }, as: :json
    end
    assert_response :unprocessable_content
    assert_equal [ I18n.t("admin.inline_add.blank_name") ], response.parsed_body["errors"]

    # 濁点違いなど照合順序で衝突する名前は、既存を示すエラーを返す
    # 照合順序 utf8mb4_0900_ai_ci は「ハ」と「バ」やひらがな/カタカナを同一視するため、
    # 見た目の違う名前でもユニーク制約に当たる。黙って別のジャンルを選ばせず理由を返す。
    existing = Genre.create!(name: "ハンド", parent: genres(:medium_japanese), level: :small)

    assert_no_difference -> { Genre.count } do
      post admin_genres_path, params: { name: "バンド", parent_id: genres(:medium_japanese).id }, as: :json
    end

    assert_response :unprocessable_content
    assert_includes response.parsed_body["errors"].first, existing.name
  end
end
