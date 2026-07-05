# 管理コンソールのトップ(/admin)。収録状況の把握と、登録・アノテーションへの入口。
class Admin::DashboardController < Admin::BaseController
  def index
    @word_count = Word.count
    @annotated_count = Word.annotated.count
    @unannotated_count = Word.unannotated.count
    @sense_count = WordSense.count
  end
end
