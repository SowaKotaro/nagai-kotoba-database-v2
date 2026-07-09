require "test_helper"

# タグ統括管理。ジャンル等のマスタを横断して一覧・リネーム・削除・統合する。
class Admin::TagsControllerTest < ActionDispatch::IntegrationTest
  # --- 認可: 未認証は弾く ---
  test "未認証だとハブはログインへリダイレクト" do
    get admin_tags_path
    assert_redirected_to new_session_path
  end

  test "未認証だと種別一覧はログインへリダイレクト" do
    get admin_tag_kind_path("entity_types")
    assert_redirected_to new_session_path
  end

  test "未認証だと更新できずログインへリダイレクト" do
    et = entity_types(:person_name)
    patch admin_tag_path("entity_types", et), params: { tag: { name: "改名" } }
    assert_redirected_to new_session_path
    assert_equal "人名", et.reload.name
  end

  test "未認証だと削除できずログインへリダイレクト" do
    et = entity_types(:person_name)
    assert_no_difference -> { EntityType.count } do
      delete admin_tag_path("entity_types", et)
    end
    assert_redirected_to new_session_path
  end

  test "未認証だと統合できずログインへリダイレクト" do
    post admin_merge_tags_path("parts_of_speech"),
         params: { source_id: parts_of_speech(:noun).id, target_id: parts_of_speech(:verb).id }
    assert_redirected_to new_session_path
    assert PartOfSpeech.exists?(parts_of_speech(:noun).id)
  end

  # --- 認証済み ---
  test "ハブ・種別一覧・編集画面が表示できる" do
    sign_in_as(Admin.take)
    get admin_tags_path
    assert_response :success

    get admin_tag_kind_path("genres")
    assert_response :success

    get admin_edit_tag_path("entity_types", entity_types(:person_name))
    assert_response :success
  end

  test "未知の種別は 404" do
    sign_in_as(Admin.take)
    get admin_tag_kind_path("admins")
    assert_response :not_found
  end

  test "リネームすると付与済みデータの表示名が変わる" do
    sign_in_as(Admin.take)
    patch admin_tag_path("entity_types", entity_types(:book_title)), params: { tag: { name: "作品名" } }
    assert_redirected_to admin_tag_kind_path("entity_types")
    assert_equal "作品名", word_senses(:murder).reload.entity_type.name
  end

  test "重複名でのリネームは 422 で再描画" do
    sign_in_as(Admin.take)
    patch admin_tag_path("parts_of_speech", parts_of_speech(:verb)), params: { tag: { name: "名詞" } }
    assert_response :unprocessable_entity
    assert_equal "動詞", parts_of_speech(:verb).reload.name
  end

  test "未使用タグは削除できる" do
    sign_in_as(Admin.take)
    assert_difference -> { EntityType.count }, -1 do
      delete admin_tag_path("entity_types", entity_types(:person_name))
    end
    assert_redirected_to admin_tag_kind_path("entity_types")
  end

  test "使用中タグの削除はブロックされる" do
    sign_in_as(Admin.take)
    assert_no_difference -> { EntityType.count } do
      delete admin_tag_path("entity_types", entity_types(:book_title))
    end
    assert_redirected_to admin_tag_kind_path("entity_types")
    assert_equal I18n.t("admin.tags.flash.destroy_blocked", name: "書籍名"), flash[:alert]
  end

  test "統合すると統合元が消えデータが付け替わる" do
    sign_in_as(Admin.take)
    post admin_merge_tags_path("parts_of_speech"),
         params: { source_id: parts_of_speech(:noun).id, target_id: parts_of_speech(:verb).id }
    assert_redirected_to admin_tag_kind_path("parts_of_speech")
    assert_not PartOfSpeech.exists?(parts_of_speech(:noun).id)
    assert_equal parts_of_speech(:verb), word_senses(:murder).reload.part_of_speech
  end

  test "統合元・統合先が未指定なら alert" do
    sign_in_as(Admin.take)
    post admin_merge_tags_path("parts_of_speech"), params: { source_id: parts_of_speech(:noun).id }
    assert_redirected_to admin_tag_kind_path("parts_of_speech")
    assert_equal I18n.t("admin.tags.flash.merge_no_target"), flash[:alert]
  end

  test "階層違いのジャンル統合は alert で拒否" do
    sign_in_as(Admin.take)
    post admin_merge_tags_path("genres"),
         params: { source_id: genres(:small_novel).id, target_id: genres(:medium_japanese).id }
    assert_redirected_to admin_tag_kind_path("genres")
    assert PartOfSpeech.exists?(parts_of_speech(:noun).id)
    assert Genre.exists?(genres(:small_novel).id)
  end
end
