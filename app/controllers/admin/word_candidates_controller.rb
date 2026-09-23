# 登録予定単語の一覧・upload・手直し。
#
# 一覧はステータスで絞り込み、語を選んで「行いたい処理」を押すと、その段の画面へ移る
# (expand に回す語と、そのまま duplicate に回す語をここで分ける。選別もここで行う)。
# 各段の画面(expand・duplicate・notation)は Admin::Candidates:: の下にある。
class Admin::WordCandidatesController < Admin::BaseController
  PER_PAGE = 200

  before_action :set_candidate, only: %i[edit update]

  def index
    @status = params[:status].presence_in(WordCandidate.statuses.keys)
    @page = [ params[:page].to_i, 1 ].max
    @status_counts = WordCandidate.group(:status).count

    scope = @status ? WordCandidate.where(status: @status) : WordCandidate.all
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @candidates = scope.in_tree_order.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
  end

  def new
    @intake = WordCandidateIntake.new(text: params[:text])
  end

  def create
    @intake = WordCandidateIntake.new(intake_params)
    if @intake.surfaces.empty?
      flash.now[:alert] = t(".empty")
      return render :new, status: :unprocessable_content
    end
    if @intake.too_many?
      flash.now[:alert] = t(".too_many", max: WordCandidateIntake::MAX_LINES)
      return render :new, status: :unprocessable_content
    end

    result = @intake.call
    redirect_to admin_word_candidates_path(status: "upload"),
                notice: intake_summary(result), alert: result.errors.presence&.join(" / ")
  end

  def edit
  end

  def update
    if @candidate.update(candidate_params)
      redirect_to admin_word_candidates_path(status: @candidate.status), notice: t(".updated", surface: @candidate.surface)
    else
      render :edit, status: :unprocessable_content
    end
  end

  # 選択した語に処理を当てる。expand・duplicate へ回したら、その段の画面へ移る。
  def bulk
    action = params[:commit].presence_in(WordCandidate::ACTIONS.keys)
    return redirect_back_to_index(alert: t(".no_action")) unless action

    candidates = WordCandidate.where(id: params[:candidate_ids]).to_a
    return redirect_back_to_index(alert: t(".no_selection")) if candidates.empty?

    WordCandidate.apply_action!(candidates, action)
    notice = t(".applied", count: candidates.size, status: t("admin.word_candidates.statuses.#{WordCandidate::ACTIONS[action]}"))
    case action
    when "to_expand" then redirect_to admin_candidates_expansion_path, notice: notice
    when "to_duplicate" then redirect_to admin_candidates_duplicate_check_path, notice: notice
    else redirect_back_to_index(notice: notice)
    end
  end

  private

  def set_candidate
    @candidate = WordCandidate.find(params[:id])
  end

  def intake_params
    params.require(:word_candidate_intake).permit(:text)
  end

  # 状態は一覧の処理ボタンと各段の画面で動かす(ここでは受けない)。
  def candidate_params
    params.require(:word_candidate).permit(:surface, :note)
  end

  # upload 結果の要約(新規 N 語 / 既に入っていた語の内訳)。
  def intake_summary(result)
    parts = [ t(".created", count: result.created) ]
    result.existing.each do |status, count|
      parts << t(".existing", status: t("admin.word_candidates.statuses.#{status}"), count: count)
    end
    parts.join(" / ")
  end

  # 絞り込みとページを保ったまま一覧へ戻す。
  def redirect_back_to_index(**flash_options)
    redirect_to admin_word_candidates_path(params.permit(:status, :page).to_h.compact_blank), **flash_options
  end
end
