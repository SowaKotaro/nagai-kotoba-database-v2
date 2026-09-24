# 登録予定単語の各段(仕分け・拡張・表記・登録待ち・すべての語)の画面の基底。
# 調査結果の取り込みと、語ごとに選んだ処理の確定、その結果の知らせ方をそろえる。
class Admin::Candidates::BaseController < Admin::BaseController
  # 取り込み結果の要約に並べる順(取り込めた語 → 増えた語 → 見送った語)。
  IMPORT_SUMMARY_ORDER = %i[seeds notated renamed doubtful split created existing registered collided stale unknown errors].freeze

  private

  # 調査スキルの出力 JSON を取り込み、次に見る画面へ移る。読めない JSON はフォームを出し直す。
  def run_import(importer_class, redirect_to_path)
    result = importer_class.new(params[:json]).call
    unless result
      flash.now[:alert] = t("admin.word_candidates.import.invalid_json")
      @json = params[:json]
      load_stage
      return render :show, status: :unprocessable_content
    end

    redirect_to redirect_to_path, notice: import_summary(result), alert: result.messages.first(20).join(" / ").presence
  end

  # 取り込み結果の要約(件数のある項目だけを並べる)。
  def import_summary(result)
    IMPORT_SUMMARY_ORDER.filter_map do |key|
      count = result.counts[key]
      t("admin.word_candidates.import_results.#{key}", count: count) if count.positive?
    end.join(" / ").presence || t("admin.word_candidates.import_results.nothing")
  end

  # 画面で語ごとに選んだ処理(decisions[ID] = 処理)を当て、移した先ごとの語数を返す。
  def apply_decisions(statuses:, choices:)
    decisions = params.permit(decisions: {})[:decisions] || {}
    WordCandidateDecisions.new(decisions, statuses: statuses, choices: choices).call
  end

  # 確定の結果(「表記待ち 9 語 / 不要 1 語」)。流れの順に並べる。何も動かなければ nil。
  def decisions_summary(counts)
    counts.sort_by { |status, _| WordCandidate.statuses.fetch(status) }.map do |status, count|
      t("admin.word_candidates.decisions.moved", status: t("admin.word_candidates.statuses.#{status}"), count: count)
    end.join(" / ").presence
  end
end
