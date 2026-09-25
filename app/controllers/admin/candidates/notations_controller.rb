# 表記: 表記待ちの語を /notation 用に書き出し、結果を取り込み、返ってきた表記と立項スコアを確かめて
# 語ごとに 採用 / 保留 / 除外 を選んで確定する。採用した語は登録待ちになる。
class Admin::Candidates::NotationsController < Admin::Candidates::BaseController
  def show
    load_stage
  end

  def import
    run_import(WordCandidateNotationImport, admin_candidates_notation_path(anchor: "review"), waiting: "notating")
  end

  def update
    counts = apply_decisions(statuses: %w[notated], choices: WordCandidateReview::CHOICES[:notation])
    notice = decisions_summary(counts)
    return redirect_to admin_candidates_notation_path, alert: t(".nothing") unless notice

    next_path = counts["ready"].positive? ? admin_candidates_registration_path : admin_candidates_notation_path
    redirect_to next_path, notice: notice
  end

  private

  def load_stage
    @export = WordCandidateExport.new("notation")
    @review = WordCandidateReview.new(WordCandidate.notated.in_tree_order, context: :notation)
  end
end
