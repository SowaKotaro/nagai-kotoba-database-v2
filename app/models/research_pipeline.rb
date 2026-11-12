# 調査の自動実行の司令塔(rake research:auto。ローカルの cron から動かす)。本番では使わない。
#
# 1 回の起動でやること:
#   1. 排他ロックを取る(前の起動がまだ動いていれば何もしない)
#   2. 途中の run があれば続きから、無ければ前回の run から INTERVAL_DAYS 日経っていれば新しい run を始める
#      (公開語の写しを取り直し、seeds.txt から未使用の種語を SEEDS_PER_RUN 語取り出す)
#   3. run を /expand → /notation → /reading と最後まで通す(段の間のふるいは ResearchRun)
#   4. inbox に annotation の書き出しが置いてあれば /annotation に回す(ResearchAnnotationBatch)
# 段が失敗したら(利用上限・時間切れ・出力が壊れていた)そこで止め、次の起動でやり直す。
# 起動の時刻を逃しても(WSL が落ちていた等)、次に cron が動いたときに期限を見て追いつく。
#
# 本番への書き込みは一切しない。一括登録・提案の取り込み・承認は人が管理画面で行う。
# 置き場所はすべて research/auto/ の下(gitignore)。手順は research/README.md。
# 種別: 書き込み処理。
class ResearchPipeline
  ROOT = Rails.root.join("research/auto")
  SEEDS_PATH = Rails.root.join("research/inputs/seeds.txt")
  # 1 run で取り出す種語の数(/expand は 1 種語あたり最大 30 語集める。スキルの上限)。
  SEEDS_PER_RUN = 5
  # 新しい run を始める間隔(日)。日付で比べる(時刻で比べると、cron の数秒の揺れで 1 回飛ぶ)。
  INTERVAL_DAYS = 2
  COMMANDS = { "expand" => "/expand", "notation" => "/notation", "reading" => "/reading" }.freeze
  # seeds.txt の行頭の番号・記号(「948. 」「- 」「・」)。
  SEED_PREFIX = /\A\s*(?:\d+[.)．]|[-・])\s*/
  # seeds.txt の区切り線(「---」。オーナーが手で使った位置の目印に引いていた)。種語ではないので読み飛ばす。
  SEED_SEPARATOR = /\A\s*-{3,}\s*\z/

  def initialize(root: ROOT, seeds_path: SEEDS_PATH, runner: ClaudeResearchRunner.new, fetcher: nil, output: $stdout)
    @root = Pathname(root)
    @seeds_path = Pathname(seeds_path)
    @runner = runner
    @fetcher = fetcher || LlmsFullFetcher.new(corpus_path)
    @output = output
  end

  def call
    FileUtils.mkdir_p(@root)
    @root.join(".lock").open(File::RDWR | File::CREAT) do |lock|
      next log("前の起動がまだ動いているため、何もせずに終わります") unless lock.flock(File::LOCK_EX | File::LOCK_NB)

      run = unfinished_run || start_run
      advance(run) if run
      annotate_inbox
    end
  end

  def runs_root = @root.join("runs")
  def corpus_path = @root.join("corpus/llms-full.txt")
  def ledger = @ledger ||= ResearchLedger.new(@root.join("ledger.tsv"))
  def inbox_path = @root.join("inbox/annotation.json")
  def annotation_root = @root.join("annotation")

  # 前回の run から INTERVAL_DAYS 日経ったか(run がまだ無ければ真)。
  def due?
    last = ResearchRun.all(runs_root).last
    last.nil? || Date.current >= last.created_on + INTERVAL_DAYS
  end

  # seeds.txt のうち、台帳で使っていない種語を先頭から count 語。
  def next_seeds(count = SEEDS_PER_RUN)
    return [] unless @seeds_path.exist?

    used = ledger.used_seeds
    @seeds_path.each_line.grep_v(SEED_SEPARATOR).map { |line| line.sub(SEED_PREFIX, "").strip }.reject(&:blank?).uniq
               .reject { |seed| used.include?(seed) }.first(count)
  end

  private

  def unfinished_run
    ResearchRun.all(runs_root).find { |run| !run.finished? }
  end

  def start_run
    return log("新しい run はまだ始めません(前回から #{INTERVAL_DAYS} 日経っていない)") unless due?

    seeds = next_seeds
    return log("seeds.txt に未使用の種語が残っていません") if seeds.empty?

    log("公開語の写し: #{@fetcher.call}")
    return log("公開語の写し(#{corpus_path})が無いため、run を始めません") unless corpus

    run = ResearchRun.create(runs_root, seeds:, corpus_fetched_at: corpus_path.mtime, ledger:)
    log("run #{run.id} を始めます: #{seeds.join("、")}")
    run
  end

  # run を最後の段まで進める。段が失敗したら止める(次の起動でやり直す)。
  def advance(run)
    until run.finished?
      stage = run.stage
      run.write_input
      FileUtils.rm_f(run.output_path)
      prompt = [ COMMANDS.fetch(stage), relative(run.input_path), "--out", relative(run.output_path.dirname) ]
      prompt << "--auto" if stage == "expand"
      ran = @runner.call(prompt.join(" "), log_path: run.output_path.dirname.join("claude.log"))
      absorbed = ran && run.output_path.exist? && run.absorb(run.output_path.read, known: known_words(run), ledger:)
      run.record_failure unless absorbed
      next log("run #{run.id}: #{stage} を通しました(残り #{run.words.size} 語)") if absorbed

      return log("run #{run.id}: #{stage} に失敗しました(#{run.attempts} 回目。#{run.stage == ResearchRun::ABORTED ? "run を止めました" : "次の起動でやり直します"})")
    end
    log("run #{run.id}: #{run.stage}(#{run.directory.join("summary.md")})")
  end

  def annotate_inbox
    ResearchAnnotationBatch.receive(inbox_path, annotation_root) if inbox_path.exist?
    ResearchAnnotationBatch.pending(annotation_root).each do |batch|
      prompt = [ "/annotation", relative(batch.input_path), "--out", relative(batch.directory) ].join(" ")
      ran = @runner.call(prompt, log_path: batch.log_path)
      next log("annotation #{batch.directory.basename}: 提案 JSON を書き出しました(#{batch.output_path})") if ran && batch.done?

      batch.record_failure
      log("annotation #{batch.directory.basename}: 失敗しました(#{batch.attempts} 回目)")
    end
  end

  def corpus
    return @corpus if defined?(@corpus)

    @corpus = ResearchCorpus.load(corpus_path)
  end

  # 重複照合の相手: 公開済みの語の読みすべてと、台帳の語(この run の行を除く。前の段で落とした兄弟に、
  # 通した側が次の段で当たらないように。この run の中の照合は ResearchRun が順に足していく)。
  def known_words(run)
    published = Array(corpus).flat_map do |entry|
      entry.readings.empty? ? [ [ entry.surface, nil ] ] : entry.readings.map { |reading| [ entry.surface, reading ] }
    end
    published + ledger.known_words(except_run: run.id)
  end

  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  def log(message)
    @output.puts("[#{Time.current.strftime("%Y-%m-%d %H:%M:%S")}] #{message}")
    nil
  end
end
