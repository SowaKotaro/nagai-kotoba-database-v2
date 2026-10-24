# 単語の修正の一覧で選択した語への、共通属性のまとめての適用(Issue 37)。ロジックは BulkAnnotation が担う。
# 逆向き(まとめて外す)は Admin::BulkDetachmentsController。
class Admin::BulkAnnotationsController < Admin::BaseController
  # 適用後も一覧の検索・絞り込み・ページ位置を保つ(word_list_params)。
  include Admin::WordListParams

  def create
    bulk = BulkAnnotation.new(bulk_annotation_params)

    if bulk.valid?
      result = bulk.apply
      redirect_to admin_words_path(word_list_params), notice: applied_message(result)
    else
      redirect_to admin_words_path(word_list_params), alert: bulk.errors.full_messages.to_sentence
    end
  end

  private

  # 選択した語の id は、まとめて外すパネルと同じフォームで共有するので名前空間の外(word_ids[])で受ける
  # (admin/words/_bulk_panels)。
  def bulk_annotation_params
    params.require(:bulk_annotation).permit(
      :genre_id, :entity_type_id, :part_of_speech_id, :meaning_template, :mark_annotated,
      :linguistic_feature_id, :feature_target, :feature_target_reading,
      word_origin_ids: []
    ).merge(word_ids: params.permit(word_ids: [])[:word_ids])
  end

  def applied_message(result)
    message = if result.skipped.positive?
      t("admin.bulk_annotations.applied_with_skipped", applied: result.applied, skipped: result.skipped)
    else
      t("admin.bulk_annotations.applied", applied: result.applied)
    end
    return message if result.feature_skipped.zero?

    message + t("admin.bulk_annotations.feature_skipped", count: result.feature_skipped)
  end
end
