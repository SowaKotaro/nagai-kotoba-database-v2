# 登録予定単語の1語: 表示(show)と、表層形・メモの手直し(edit/update)。
#
# 仕分け・表記の確認の画面では、行の「語」の部分(turbo-frame)の中でこの edit を開き、保存・取りやめると
# show の同じ frame に戻る(ほかの行で選んだ処理を失わないよう、画面ごとは読み直さない)。
# 状態はここでは動かさない(各段の画面と「すべての語」で動かす)。
class Admin::WordCandidatesController < Admin::BaseController
  before_action :set_candidate

  def show
    @matches = WordCandidateDuplicateCheck.new.matches_for(@candidate.surface, except: @candidate)
  end

  def edit
  end

  def update
    if @candidate.update(candidate_params)
      redirect_to admin_word_candidate_path(@candidate), notice: t(".updated", surface: @candidate.surface)
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_candidate
    @candidate = WordCandidate.find(params[:id])
  end

  def candidate_params
    params.require(:word_candidate).permit(:surface, :note)
  end
end
