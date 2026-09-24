# すべての語: 登録予定単語を状態で絞り込み、表層形で探す。選んだ語をまとめて仕分けに戻す・保留・不要にする
# (本流から外した語を戻すとき、登録待ちから外すときに使う。仕分けや確認は各段の画面で行う)。
class Admin::Candidates::ListsController < Admin::Candidates::BaseController
  # 一度に並べる上限。ページは分けず、越えたら絞り込んでもらう(ページ送りで行き来させないため)。
  LIMIT = 1000

  def show
    @status = params[:status].presence_in(WordCandidate.statuses.keys)
    @query = params[:q].to_s.strip
    scope = WordCandidate.all
    scope = scope.where(status: @status) if @status
    scope = scope.matching(@query) if @query.present?
    @total_count = scope.count
    @candidates = scope.in_tree_order.limit(LIMIT).to_a
  end

  # 選んだ語を移す。登録済みの語は一括登録で収録された語なので動かさない。
  def update
    move = params[:move].presence_in(WordCandidate::MOVES)
    return redirect_back_to_list(alert: t(".no_move")) unless move

    candidates = WordCandidate.where(id: params.permit(candidate_ids: [])[:candidate_ids]).where.not(status: :registered).to_a
    return redirect_back_to_list(alert: t(".no_selection")) if candidates.empty?

    WordCandidate.transaction do
      candidates.each { |candidate| candidate.update!(status: move) }
    end
    redirect_back_to_list(notice: t(".moved", count: candidates.size, status: t("admin.word_candidates.statuses.#{move}")))
  end

  private

  # 絞り込みと検索を保ったまま一覧へ戻す。
  def redirect_back_to_list(**flash_options)
    redirect_to admin_candidates_list_path(params.permit(:status, :q).to_h.compact_blank), **flash_options
  end
end
