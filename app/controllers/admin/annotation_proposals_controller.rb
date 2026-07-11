# Claude Code 連携アノテーションの受け渡し口(Issue 38)。
#   export: 調査用データ(対象語 + マスタ一覧)のコピー用 JSON を表示する。
#   new/create: word-annotation-research スキルの出力 JSON を貼り付けて下書き保存する。
# 提案の承認(反映・保存)はアノテーション・コンソール側で行う。
class Admin::AnnotationProposalsController < Admin::BaseController
  EXPORT_DEFAULT_LIMIT = 50
  EXPORT_MAX_LIMIT = 200

  # 未注釈の語を id 順に書き出す(件数指定可)。
  #   既定: まだ提案が無い語の先頭から書き出す。
  #   範囲指定(from_id / to_id): その word_id 範囲を書き出す。既に下書き提案がある語も
  #     含めるので、一度取り込んだ語を絞り込んで再調査させたいときに使う。
  def export
    @limit = (params[:limit].presence || EXPORT_DEFAULT_LIMIT).to_i.clamp(1, EXPORT_MAX_LIMIT)
    @from_id = params[:from_id].presence&.to_i
    @to_id = params[:to_id].presence&.to_i

    words = Word.unannotated.includes(:word_senses).order(:id)
    if @from_id || @to_id
      words = words.where("words.id >= ?", @from_id) if @from_id
      words = words.where("words.id <= ?", @to_id) if @to_id
    else
      words = words.where.missing(:annotation_proposal)
    end

    words = words.limit(@limit)
    @word_count = words.size
    @export_json = AnnotationResearchExport.new(words).to_json
  end

  def new
  end

  def create
    result = AnnotationProposalImport.new(params[:proposals_json]).import

    if result
      redirect_to new_admin_annotation_proposal_path, notice: import_message(result)
    else
      flash.now[:alert] = t("admin.annotation_proposals.parse_error")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def import_message(result)
    if result.unknown_word_ids.any?
      t("admin.annotation_proposals.imported_with_unknown",
        saved: result.saved, unknown: result.unknown_word_ids.join(", "))
    else
      t("admin.annotation_proposals.imported", saved: result.saved)
    end
  end
end
