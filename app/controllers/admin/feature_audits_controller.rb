# 言語学的特徴の点検(特徴の新設・判定基準の見直しのあとに、公開済みの語すべてを見直す)。
#   show: 公開済みの語と、いま付いている特徴を書き出す(コピー欄と JSON ファイル)。点検結果の貼り付け欄も置く。
#   preview: 貼った点検結果(word-feature-audit スキルの出力)を、足す・外すの行の一覧にして選ばせる。保存しない。
#   apply: 選んだ行だけを適用する。貼った JSON を読み直して検証し直してから書き込む。
# 提案(annotation_proposals)は使わない: 公開済みの語を 1 語ずつコンソールで開かずに済むようにし、
# 外す変更も同じ画面で適用するため。
class Admin::FeatureAuditsController < Admin::BaseController
  EXPORT_DEFAULT_LIMIT = 500
  # 公開済みの語をまとめて書き出せる上限。点検は全件を見るので、提案の書き出しより大きく取る。
  EXPORT_MAX_LIMIT = 3000

  def show
    load_export
    respond_to do |format|
      format.html
      format.json do
        send_data @export.to_json, type: :json, disposition: "attachment", filename: export_filename
      end
    end
  end

  def preview
    @result_json = params[:result_json].to_s
    @rows = FeatureAuditImport.new(@result_json).rows
    return if @rows

    load_export
    flash.now[:alert] = t("admin.feature_audits.parse_error")
    render :show, status: :unprocessable_content
  end

  def apply
    rows = FeatureAuditImport.new(params[:result_json]).rows
    return redirect_to admin_feature_audit_path, alert: t("admin.feature_audits.parse_error") unless rows

    result = FeatureAuditApplication.new(rows, params[:selected]).apply
    redirect_to admin_feature_audit_path,
                notice: t("admin.feature_audits.applied", added: result.added, removed: result.removed, words: result.words)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_feature_audit_path, alert: t("admin.feature_audits.failed", message: e.message)
  end

  private

  def load_export
    @limit = (params[:limit].presence || EXPORT_DEFAULT_LIMIT).to_i.clamp(1, EXPORT_MAX_LIMIT)
    @from_id = params[:from_id].presence&.to_i
    @to_id = params[:to_id].presence&.to_i
    words = FeatureAuditExport.target_words(limit: @limit, from_id: @from_id, to_id: @to_id)
    @export = FeatureAuditExport.new(words, feature_names: params[:features])
    @word_count = words.size
    @published_count = Word.annotated.count
    @linguistic_features = LinguisticFeature.in_glossary_order
  end

  def export_filename
    range = [ @from_id, @to_id ].compact.join("-").presence || "all"
    "feature-audit-#{range}.json"
  end
end
