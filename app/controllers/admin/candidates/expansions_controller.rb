# expand の段: 元の語を /expand 用に書き出し、結果を取り込み、増えた語ごと duplicate へ送る。
class Admin::Candidates::ExpansionsController < Admin::Candidates::BaseController
  def show
    load_step
  end

  def import
    run_import(WordCandidateExpansionImport)
  end

  # 取り込み済みの語(元の語と増えた語)をまとめて duplicate へ。まだ結果の無い元の語は残る。
  def update
    candidates = WordCandidate.expand.where.not(expanded_at: nil).to_a
    return redirect_to admin_candidates_expansion_path, alert: t(".empty") if candidates.empty?

    move_all(candidates, :duplicate)
    redirect_to admin_candidates_duplicate_check_path, notice: t(".moved", count: candidates.size)
  end

  private

  def load_step
    @export = WordCandidateExport.new("expand")
    @results = WordCandidate.expand.where.not(expanded_at: nil).in_tree_order.to_a
  end
end
