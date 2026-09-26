# 管理コンソールのトップ(/admin)。収録状況の把握と、登録・アノテーションへの入口。
class Admin::DashboardController < Admin::BaseController
  def index
    @word_count = Word.count
    @annotated_count = Word.annotated.count
    @unannotated_count = Word.unannotated.count
    @sense_count = WordSense.count
    # 注釈の進捗(%)。切り捨てる: 1 語でも残っていれば 100% と出さない
    @annotated_percent = @word_count.zero? ? 0 : @annotated_count * 100 / @word_count
    # 作業のカードに添える「まだ手を付けていない件数」。キーは admin_sections の key と揃える
    @pending_counts = {
      annotations: @unannotated_count,
      # 登録予定単語のうち、前処理の途中(upload〜notation)と要判断にいる語の数
      candidates: WordCandidate.in_progress.count,
      # 公開側から届いた収録リクエストのうち、まだ手を付けていない件数(Issue 75)
      requests: WordRequestItem.pending.count
    }
  end
end
