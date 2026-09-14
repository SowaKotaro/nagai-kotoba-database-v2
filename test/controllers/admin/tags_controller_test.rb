require "test_helper"

# タグ統括管理。ジャンル等のマスタを横断して一覧・リネーム・削除・統合する。
# 使用件数・削除可否・統合の中身は TagMasterTest / GenreTest / TagKindTest で見る。
class Admin::TagsControllerTest < ActionDispatch::IntegrationTest
  # --- 認可: 未認証は弾く ---
  test "未認証だと一覧・更新・削除・統合・追加はログインへ戻し、何も変えない" do
    get admin_tags_path
    assert_redirected_to new_session_path
    get admin_tag_kind_path("entity_types")
    assert_redirected_to new_session_path

    person = entity_types(:person_name)
    patch admin_tag_path("entity_types", person), params: { tag: { name: "改名" } }
    assert_redirected_to new_session_path
    assert_equal "人名", person.reload.name

    assert_no_difference -> { EntityType.count } do
      delete admin_tag_path("entity_types", person)
    end
    assert_redirected_to new_session_path

    post admin_merge_tags_path("parts_of_speech"),
         params: { source_id: parts_of_speech(:noun).id, target_id: parts_of_speech(:verb).id }
    assert_redirected_to new_session_path
    assert PartOfSpeech.exists?(parts_of_speech(:noun).id)

    assert_no_difference -> { LinguisticFeature.count } do
      post admin_create_tag_path("linguistic_features"), params: { tag: { name: "音便" } }
    end
    assert_redirected_to new_session_path
  end

  # --- 表示 ---
  test "ハブと編集画面(現在の名前つき)を表示でき、未知の種別は 404" do
    sign_in_as(Admin.take)
    get admin_tags_path
    assert_response :success

    get admin_edit_tag_path("entity_types", entity_types(:book_title))
    assert_response :success
    assert_select "#tag_name[value=?]", "書籍名"

    get admin_tag_kind_path("admins")
    assert_response :not_found
  end

  test "種別一覧は使用中のタグに削除ボタンを出さず、ジャンルは木の順に階層ぶんインデントして並べる" do
    sign_in_as(Admin.take)
    get admin_tag_kind_path("entity_types")
    assert_response :success
    # 人名(未使用)の行には削除ボタン、書籍名(語義に付与済み)の行は「使用中」
    assert_select "tbody tr", text: /人名/ do
      assert_select "button", text: I18n.t("admin.tags.destroy")
    end
    assert_select "tbody tr", text: /書籍名/ do
      assert_select "button", text: I18n.t("admin.tags.destroy"), count: 0
      assert_select ".tag-table__inuse", text: I18n.t("admin.tags.in_use")
    end

    # fixtures は 文学 › 日本文学 › 小説 の一系統。深さ優先で大→中→小の順に並ぶ
    get admin_tag_kind_path("genres")
    assert_response :success
    names = css_select(".tag-table tbody td.tag-table__name").map { |cell| cell.at_css("a").text.strip }
    assert_equal %w[文学 日本文学 小説], names
    assert_select "td.tag-table__name--large a", text: "文学"
    assert_select "td.tag-table__name--medium a", text: "日本文学"
    assert_select "td.tag-table__name--small a", text: "小説"
  end

  # --- 更新・削除・統合 ---
  test "リネームすると付与済みデータの表示名が変わり、重複名は 422 で再描画する" do
    sign_in_as(Admin.take)
    patch admin_tag_path("entity_types", entity_types(:book_title)), params: { tag: { name: "作品名" } }
    assert_redirected_to admin_tag_kind_path("entity_types")
    assert_equal "作品名", word_senses(:murder).reload.entity_type.name

    patch admin_tag_path("parts_of_speech", parts_of_speech(:verb)), params: { tag: { name: "名詞" } }
    assert_response :unprocessable_entity
    assert_equal "動詞", parts_of_speech(:verb).reload.name
  end

  test "未使用タグは削除でき、使用中タグの削除はブロックする" do
    sign_in_as(Admin.take)
    assert_difference -> { EntityType.count }, -1 do
      delete admin_tag_path("entity_types", entity_types(:person_name))
    end
    assert_redirected_to admin_tag_kind_path("entity_types")

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

  test "統合先が未指定のときや、階層の違うジャンル同士は統合しない" do
    sign_in_as(Admin.take)
    post admin_merge_tags_path("parts_of_speech"), params: { source_id: parts_of_speech(:noun).id }
    assert_redirected_to admin_tag_kind_path("parts_of_speech")
    assert_equal I18n.t("admin.tags.flash.merge_no_target"), flash[:alert]
    assert PartOfSpeech.exists?(parts_of_speech(:noun).id)

    post admin_merge_tags_path("genres"),
         params: { source_id: genres(:small_novel).id, target_id: genres(:medium_japanese).id }
    assert_redirected_to admin_tag_kind_path("genres")
    assert flash[:alert].present?
    assert Genre.exists?(genres(:small_novel).id)
  end

  # --- 新規追加(言語学的特徴のみ) ---
  test "言語学的特徴を追加でき、追加パネルは特徴の一覧にだけ出る" do
    sign_in_as(Admin.take)
    get admin_tag_kind_path("linguistic_features")
    assert_select "details.tag-add", 1
    get admin_tag_kind_path("parts_of_speech")
    assert_select "details.tag-add", 0

    assert_difference -> { LinguisticFeature.count }, 1 do
      post admin_create_tag_path("linguistic_features"), params: { tag: { name: "音便" } }
    end
    assert_redirected_to admin_tag_kind_path("linguistic_features")
    assert_equal I18n.t("admin.tags.flash.created", name: "音便"), flash[:notice]
  end

  test "空や既存と同じ名前は 422 で再描画し、追加を許可していない種別は 404" do
    sign_in_as(Admin.take)
    assert_no_difference -> { LinguisticFeature.count } do
      post admin_create_tag_path("linguistic_features"), params: { tag: { name: "" } }
      assert_response :unprocessable_entity
      assert_select "ul.form-errors li"

      post admin_create_tag_path("linguistic_features"), params: { tag: { name: "連濁" } }
      assert_response :unprocessable_entity
    end

    assert_no_difference -> { PartOfSpeech.count } do
      post admin_create_tag_path("parts_of_speech"), params: { tag: { name: "形容詞" } }
    end
    assert_response :not_found
  end

  # --- seed 管理タグの印と警告(Issue 49) ---
  test "seed 管理タグには一覧で seed 印、編集画面で警告が出る" do
    sign_in_as(Admin.take)

    get admin_tag_kind_path("word_origins")
    assert_response :success
    assert_select "span.tag-table__seed", minimum: 1 # 英語(カタログ収載)に印が付く

    get admin_edit_tag_path("word_origins", word_origins(:eigo))
    assert_response :success
    assert_select ".seed-warning", 1
  end

  test "カタログ外のタグには seed 印・警告が出ない" do
    sign_in_as(Admin.take)

    # 和語はカタログ外(UI 追加扱い)なので警告なし
    get admin_edit_tag_path("word_origins", word_origins(:wago))
    assert_response :success
    assert_select ".seed-warning", count: 0

    # エンティティタイプは種別ごと seed 管理外。印も注記も出ない
    get admin_tag_kind_path("entity_types")
    assert_response :success
    assert_select "span.tag-table__seed", count: 0
  end
end
