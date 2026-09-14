require "test_helper"

# アノテーション・コンソールの「その場追加」のうち、単純マスタ3種(語種・品詞・エンティティタイプ)。
# 3つとも共通処理(InlineMasterCreatable)に名前を渡すだけなので、同じ振る舞いをまとめて確かめる。
# 空白・照合順序の衝突の扱いは Admin::GenresControllerTest で見る。
class Admin::InlineMasterCreationTest < ActionDispatch::IntegrationTest
  # モデル => [作成のパス, 新しく作る名前]
  ENDPOINTS = {
    WordOrigin => [ :admin_word_origins_path, "タミル語" ],
    PartOfSpeech => [ :admin_parts_of_speech_path, "形容詞" ],
    EntityType => [ :admin_entity_types_path, "地名" ]
  }.freeze

  test "未認証だと作成できない" do
    ENDPOINTS.each do |model, (path, name)|
      assert_no_difference -> { model.count }, model.name do
        post public_send(path), params: { name: name }, as: :json
      end
    end
  end

  test "名前だけで作成でき、同名が既にあれば二重に作らず既存を返す" do
    sign_in_as(Admin.take)

    ENDPOINTS.each do |model, (path, name)|
      assert_difference -> { model.count }, 1, model.name do
        post public_send(path), params: { name: name }, as: :json
      end
      assert_response :success
      created = response.parsed_body
      assert_equal name, created["name"]

      assert_no_difference -> { model.count }, model.name do
        post public_send(path), params: { name: name }, as: :json
      end
      assert_response :success
      assert_equal created["id"], response.parsed_body["id"]
      assert response.parsed_body["existing"], "#{model.name} が既存を返していない"
    end
  end
end
