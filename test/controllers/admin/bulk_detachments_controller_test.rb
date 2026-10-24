require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# 一覧で選択した語から、指定した値をまとめて外す(Issue 108)。外し方の規則は BulkDetachmentTest で見る。
class Admin::BulkDetachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(admins(:one))
    @murder = words(:abc_murder)
  end

  test "選択した語から外し、件数を知らせて、検索・絞り込みを保った一覧へ戻る" do
    filters = { q: "殺人", linguistic_feature_id: linguistic_features(:rendaku).id.to_s, feature_target: "殺人" }
    post admin_bulk_detachment_path, params: filters.merge(
      word_ids: [ @murder.id ],
      # 同じフォームのまとめて付けるパネルの値も届くが、読まない
      bulk_annotation: { meaning_template: "使わない" },
      bulk_detachment: { linguistic_feature_id: linguistic_features(:rendaku).id, feature_target: "殺人" }
    )

    assert_redirected_to admin_words_path(filters)
    assert_equal "1 語から 1 件を外しました。", flash[:notice]
    assert_equal [ word_sense_features(:murder_jubako).id ], word_senses(:murder).word_sense_features.ids
    assert_not_equal "使わない", word_senses(:murder).reload.meaning
  end

  test "外すものが無ければ、そう知らせる" do
    post admin_bulk_detachment_path, params: {
      word_ids: [ words(:curry).id ], bulk_detachment: { entity_type_id: entity_types(:person_name).id }
    }

    assert_redirected_to admin_words_path
    assert_equal I18n.t("admin.bulk_detachments.nothing"), flash[:notice]
  end

  test "外すものを選んでいなければエラーを知らせて一覧へ戻す" do
    post admin_bulk_detachment_path, params: { word_ids: [ @murder.id ], bulk_detachment: { feature_target: "" } }

    assert_redirected_to admin_words_path
    assert_match "外すもの", flash[:alert]
  end
end
