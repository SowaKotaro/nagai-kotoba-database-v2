# 単語の修正の一覧で選択した語から、指定した値をまとめて外す(Issue 108)。ロジックは BulkDetachment が担う。
class Admin::BulkDetachmentsController < Admin::BaseController
  # 外したあとも一覧の検索・絞り込み・ページ位置を保つ(word_list_params)。
  include Admin::WordListParams

  # 検証は apply がトランザクションの中で行う(特徴が選んだ語すべてに付いているかを、外す直前に確かめるため)。
  def create
    bulk = BulkDetachment.new(bulk_detachment_params)
    result = bulk.apply
    redirect_to admin_words_path(word_list_params), notice: detached_message(result)
  rescue ActiveModel::ValidationError
    redirect_to admin_words_path(word_list_params), alert: bulk.errors.full_messages.to_sentence
  end

  private

  # 選択した語の id は、まとめて付けるパネルと同じフォームで共有する(Admin::BulkAnnotationsController と同じ受け方)。
  def bulk_detachment_params
    params.require(:bulk_detachment).permit(
      :linguistic_feature_id, :feature_target, :genre_id, :entity_type_id, :part_of_speech_id,
      word_origin_ids: []
    ).merge(word_ids: params.permit(word_ids: [])[:word_ids])
  end

  def detached_message(result)
    return t("admin.bulk_detachments.nothing") if result.removed.zero?

    t("admin.bulk_detachments.detached", words: result.words, removed: result.removed)
  end
end
