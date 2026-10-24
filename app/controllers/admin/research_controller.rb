# 調査データ(Claude Code 連携の入口。Issue 108)。調査用データの書き出し・特徴の再調査・提案の取り込み・
# 提案キュー・一括承認へ、流れの順に案内する。各画面の中身は Admin::AnnotationProposalsController・
# Admin::BulkProposalApprovalsController・Admin::AnnotationsController(?proposed=1)が持つ。
class Admin::ResearchController < Admin::BaseController
  def show
    @awaiting_count = Word.awaiting_research.count
    # 書き出しの画面(export_features)と同じ既定(語種に日本語を含む語だけ)で数える
    @features_unreviewed_count = FeatureResearchExport.target_senses(limit: nil, japanese_only: true).count
    @proposed_count = Word.annotation_pending.with_pending_proposal.count
  end
end
