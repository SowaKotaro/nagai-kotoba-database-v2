# duplicate の段: 収録済みの語・別表記・ほかの登録予定単語と照合し、
# チェックした語を「重複」に、残りをまとめて notation へ送る。
class Admin::Candidates::DuplicateChecksController < Admin::Candidates::BaseController
  def show
    @candidates = WordCandidate.duplicate.in_tree_order.to_a
    @matches = WordCandidateDuplicateCheck.new(@candidates).call
  end

  # 画面に出した語(shown_ids)だけを動かす(表示後に入ってきた語を確認なしで送らないため)。
  def update
    shown = WordCandidate.duplicate.where(id: params[:shown_ids]).to_a
    return redirect_to admin_candidates_duplicate_check_path, alert: t(".empty") if shown.empty?

    excluded_ids = Array(params[:duplicated_ids]).map(&:to_i)
    duplicated, rest = shown.partition { |candidate| excluded_ids.include?(candidate.id) }
    WordCandidate.transaction do
      move_all(duplicated, :duplicated)
      rest.each { |candidate| candidate.update!(status: :notation, notated_at: nil) }
    end
    redirect_to admin_candidates_notation_path, notice: t(".moved", duplicated: duplicated.size, count: rest.size)
  end
end
