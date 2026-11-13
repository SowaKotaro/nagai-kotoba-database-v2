# 調査の自動実行(ローカルの cron から動かす。本番では使わない)。規則は ResearchPipeline と ResearchRun が持つ。
namespace :research do
  desc "調査の自動実行: seeds.txt の種語を /expand → /notation → /reading と通し、一括登録に貼る語と読みを作る。" \
       "inbox の注釈の書き出しは /annotation に回す。DB には触らない(research/auto/ の下のファイルだけを書く)。" \
       "FORCE=1 で、前回の run から INTERVAL_DAYS 日経っていなくても新しい run を始める(スキル /auto が使う)"
  task auto: :environment do
    ResearchPipeline.new(force: ENV["FORCE"].present?).call
  end
end
