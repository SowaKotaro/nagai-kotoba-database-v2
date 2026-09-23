# notation の段: /notation 用に書き出し、結果を取り込み、確認した語をまとめて done へ送る。
# done の語は一括登録へ貼るためのリストとしてコピーできる(登録されると「登録済み」になる)。
class Admin::Candidates::NotationsController < Admin::Candidates::BaseController
  def show
    load_step
  end

  def import
    run_import(WordCandidateNotationImport)
  end

  # 取り込み済みの語をまとめて done へ。まだ結果の無い語は残る。
  def update
    candidates = WordCandidate.notation.where.not(notated_at: nil).to_a
    return redirect_to admin_candidates_notation_path, alert: t(".empty") if candidates.empty?

    move_all(candidates, :done)
    redirect_to admin_candidates_notation_path(anchor: "done"), notice: t(".moved", count: candidates.size)
  end

  private

  def load_step
    @export = WordCandidateExport.new("notation")
    @results = WordCandidate.notation.where.not(notated_at: nil).in_tree_order.to_a
    @done = WordCandidate.done.in_tree_order.to_a
  end
end
