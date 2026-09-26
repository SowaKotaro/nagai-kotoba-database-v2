# 仕分け(登録予定単語の入口): 語を貼り付けて追加し(create)、語ごとに 拡張 / 採用 / 保留 / 除外 を選んで
# 一度に確定する(update)。/expand で集まった語・分割でできた語もここに並ぶ。保留にした語は末尾に畳んで出す。
class Admin::Candidates::TriagesController < Admin::Candidates::BaseController
  def show
    @intake = WordCandidateIntake.new
    load_stage
  end

  def create
    @intake = WordCandidateIntake.new(intake_params)
    if (alert = intake_error)
      flash.now[:alert] = alert
      load_stage
      return render :show, status: :unprocessable_content
    end

    result = @intake.call
    redirect_to admin_candidates_triage_path, notice: intake_summary(result), alert: result.errors.presence&.join(" / ")
  end

  def update
    counts = apply_decisions(statuses: %w[triage held], choices: WordCandidateReview::CHOICES[:triage])
    notice = decisions_summary(counts)
    return redirect_to admin_candidates_triage_path, alert: t(".nothing") unless notice

    redirect_to next_stage_path(counts), notice: notice
  end

  private

  def load_stage
    @review = WordCandidateReview.new(WordCandidate.triage.in_tree_order, context: :triage)
    @held = WordCandidateReview.new(WordCandidate.held.in_tree_order, context: :triage)
  end

  def intake_params
    params.require(:word_candidate_intake).permit(:text)
  end

  def intake_error
    return t(".empty") if @intake.surfaces.empty?

    t(".too_many", max: WordCandidateIntake::MAX_LINES) if @intake.too_many?
  end

  # 追加の結果の要約(新規 N 語 / 既に入っていた語の内訳)。
  def intake_summary(result)
    parts = [ t(".created", count: result.created) ]
    result.existing.each do |status, count|
      parts << t(".existing", status: t("admin.word_candidates.statuses.#{status}"), count: count)
    end
    parts.join(" / ")
  end

  # 確定のあとに開く画面。拡張を選んだ語があれば、次は /expand に渡すので拡張の画面へ
  # (採用した語は拡張の結果と合わせて /notation に一度で渡せばよい)。採用だけなら表記の画面へ。
  def next_stage_path(counts)
    return admin_candidates_expansion_path if counts["expanding"].positive?
    return admin_candidates_notation_path if counts["notating"].positive?

    admin_candidates_triage_path
  end
end
