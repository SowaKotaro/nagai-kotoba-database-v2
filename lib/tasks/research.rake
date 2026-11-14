# 調査の自動実行(ローカルの cron から動かす。本番では使わない)。規則は ResearchPipeline と ResearchRun が持つ。
namespace :research do
  desc "調査の自動実行: seeds.txt の種語を /expand → /notation → /reading と通し、一括登録に貼る語と読みを作る。" \
       "inbox の注釈の書き出しは /annotation に回す。DB には触らない(research/auto/ の下のファイルだけを書く)。" \
       "FORCE=1 で、前回の run から INTERVAL_DAYS 日経っていなくても新しい run を始める(スキル /auto が使う)。" \
       "SEEDS=15 で、新しい run の種語をその数だけ使う(既定は SEEDS_PER_RUN。/auto 15 が使う)。" \
       "最後に、run を眺める静的なページ research/auto/index.html を作り直す(script/research_viewer.py)"
  task auto: :environment do
    seeds_per_run = ENV["SEEDS"].present? ? Integer(ENV["SEEDS"], 10, exception: false) : ResearchPipeline::SEEDS_PER_RUN
    abort "SEEDS は 1 以上の整数にしてください(#{ENV["SEEDS"]})" unless seeds_per_run&.positive?

    ResearchPipeline.new(force: ENV["FORCE"].present?, seeds_per_run:).call
    # 眺める用の静的なページ(research/auto/index.html)を作り直す。失敗しても調査の結果には響かない
    system("python3", Rails.root.join("script/research_viewer.py").to_s) || warn("research/auto/index.html を作り直せませんでした")
  end
end
