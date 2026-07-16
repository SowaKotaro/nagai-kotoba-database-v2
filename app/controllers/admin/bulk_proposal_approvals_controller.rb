# 提案の一括承認(Issue 65)。厳格ゲートを満たす提案をプレビューし、まとめて承認・公開する。
# 承認=公開は取り返しにくい操作なので、show でプレビュー(件数・語一覧)を必ず挟む。
class Admin::BulkProposalApprovalsController < Admin::BaseController
  # プレビュー: 一括対象になる提案(語)の一覧を見せる。
  def show
    @approval = BulkProposalApproval.new
  end

  # まとめて承認して公開する。適用後は提案キューへ戻す(残りは人手で確認)。
  def create
    result = BulkProposalApproval.new.approve!
    redirect_to admin_annotations_path(proposed: 1),
                notice: t("admin.bulk_proposal_approvals.approved", count: result.approved)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_bulk_proposal_approval_path,
                alert: t("admin.bulk_proposal_approvals.failed", message: e.message)
  end
end
