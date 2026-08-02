# 管理コンソールのトップ(/admin)。収録状況の把握と、登録・アノテーションへの入口。
class Admin::DashboardController < Admin::BaseController
  def index
    @word_count = Word.count
    @annotated_count = Word.annotated.count
    @unannotated_count = Word.unannotated.count
    @sense_count = WordSense.count
    # 公開側から届いた収録リクエストのうち、まだ手を付けていない件数(Issue 75)。
    @pending_request_count = WordRequestItem.pending.count
  end
end
