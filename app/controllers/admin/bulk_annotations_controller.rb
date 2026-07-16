# 管理一覧で選択した語への共通属性の一括適用(Issue 37)。ロジックは BulkAnnotation が担う。
class Admin::BulkAnnotationsController < Admin::BaseController
  def create
    bulk = BulkAnnotation.new(bulk_annotation_params)

    if bulk.valid?
      result = bulk.apply
      redirect_to admin_words_path(list_params), notice: applied_message(result)
    else
      redirect_to admin_words_path(list_params), alert: bulk.errors.full_messages.to_sentence
    end
  end

  private

  def bulk_annotation_params
    params.require(:bulk_annotation).permit(
      :genre_id, :entity_type_id, :part_of_speech_id, :meaning_template, :mark_annotated,
      word_ids: [], word_origin_ids: []
    )
  end

  # 適用後も一覧の検索・絞り込み(注釈状態・タグ)・ページ位置を保つ。
  def list_params
    params.permit(:q, :status, :page, *Admin::WordsController::TAG_FILTER_KEYS).to_h.compact_blank
  end

  def applied_message(result)
    if result.skipped.positive?
      t("admin.bulk_annotations.applied_with_skipped", applied: result.applied, skipped: result.skipped)
    else
      t("admin.bulk_annotations.applied", applied: result.applied)
    end
  end
end
