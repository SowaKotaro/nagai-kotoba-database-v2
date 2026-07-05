require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::AnnotationsControllerTest < ActionDispatch::IntegrationTest
  # コンソールは未注釈語(annotated_at なし)を対象にする。
  setup do
    @word = words(:pending_haruhi)
    @sense = word_senses(:pending)
  end

  # --- 認可: 未認証は弾く ---
  test "未認証だとコンソールはログインへリダイレクト" do
    get admin_annotation_path(@word)
    assert_redirected_to new_session_path
  end

  test "未認証だと保存できない" do
    patch admin_annotation_path(@word), params: { word: { word_senses_attributes: { "0" => { id: @sense.id, reading: @sense.reading } } } }
    assert_redirected_to new_session_path
    assert_nil @word.reload.annotated_at
  end

  test "未認証だとマスタをその場追加できない" do
    assert_no_difference -> { WordOrigin.count } do
      post admin_word_origins_path, params: { name: "タミル語" }, as: :json
    end
  end

  # --- index: 最初の未注釈へ誘導 ---
  test "index は最初の未注釈へリダイレクトする" do
    sign_in_as(Admin.take)
    get admin_annotations_path
    assert_response :redirect
    assert_match %r{/admin/annotations/\d+}, @response.redirect_url
  end

  # --- show: コンソールを描画できる(全 partial のスモーク) ---
  test "コンソールを描画できる" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word)
    assert_response :success
    assert_select "h1.ann-word", text: @word.surface
    assert_select ".ann-chip"          # 語種・品詞などのチップ
    assert_select ".ann-strip"         # 特徴の文字ストリップ枠
  end

  # --- update: 語種(多対多)・ジャンル・意味を保存し annotated_at をセット ---
  test "注釈を保存すると annotated_at がセットされ次の未注釈へ進む" do
    sign_in_as(Admin.take)
    patch admin_annotation_path(@word), params: {
      word: { word_senses_attributes: { "0" => {
        id: @sense.id, reading: @sense.reading, meaning: "更新後の意味",
        genre_id: genres(:small_novel).id, part_of_speech_id: parts_of_speech(:noun).id,
        word_origin_ids: [ word_origins(:wago).id, word_origins(:kango).id ]
      } } }
    }
    @word.reload
    assert_not_nil @word.annotated_at
    assert_equal "更新後の意味", @sense.reload.meaning
    assert_equal [ word_origins(:kango).id, word_origins(:wago).id ].sort, @sense.word_origin_ids.sort
    # 残る未注釈(pending_bermuda)へ誘導する。
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))
  end

  test "別表記と特徴をネストして保存できる" do
    sign_in_as(Admin.take)
    assert_difference -> { WordSenseVariant.count } => 1 do
      patch admin_annotation_path(@word), params: {
        word: { word_senses_attributes: { "0" => {
          id: @sense.id, reading: @sense.reading,
          word_sense_variants_attributes: { "0" => { surface: "殺人事件（別表記）", reading: "さつじんじけん" } }
        } } }
      }
    end
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))
  end

  # --- マスタのその場追加 ---
  test "語種をその場で追加できる(JSON)" do
    sign_in_as(Admin.take)
    assert_difference -> { WordOrigin.count } => 1 do
      post admin_word_origins_path, params: { name: "タミル語" }, as: :json
    end
    assert_response :success
    assert_equal "タミル語", response.parsed_body["name"]
  end

  test "小分類ジャンルをその場で追加できる(親の下に作成)" do
    sign_in_as(Admin.take)
    assert_difference -> { Genre.count } => 1 do
      post admin_genres_path, params: { name: "新しい小分類", parent_id: genres(:medium_japanese).id }, as: :json
    end
    created = Genre.find(response.parsed_body["id"])
    assert created.small?
    assert_equal genres(:medium_japanese), created.parent
  end
end
