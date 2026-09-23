# 登録予定単語の各段(expand・duplicate・notation)の画面の基底。
# 調査結果の取り込みと、その要約の出し方をそろえる。
class Admin::Candidates::BaseController < Admin::BaseController
  private

  # 調査スキルの出力 JSON を取り込み、同じ画面へ戻る。読めない JSON はフォームを出し直す。
  def run_import(importer_class)
    result = importer_class.new(params[:json]).call
    unless result
      flash.now[:alert] = t("admin.word_candidates.import.invalid_json")
      @json = params[:json]
      load_step
      return render :show, status: :unprocessable_content
    end

    redirect_to url_for(action: :show), notice: import_summary(result), alert: result.messages.first(20).join(" / ").presence
  end

  # 取り込み結果の要約(件数のある項目だけを並べる)。
  def import_summary(result)
    result.counts.filter_map do |key, count|
      t("admin.word_candidates.import_results.#{key}", count: count) if count.positive?
    end.join(" / ").presence || t("admin.word_candidates.import_results.nothing")
  end

  # 段の最後のボタン: 語をまとめて次のステータスへ送る。
  def move_all(candidates, status)
    WordCandidate.transaction do
      candidates.each { |candidate| candidate.update!(status: status) }
    end
  end
end
