require "test_helper"

class ResearchPipelineTest < ActiveSupport::TestCase
  # スキルの代わり。プロンプト「/コマンド 入力 --out ディレクトリ [--auto]」を受け、responder に書かせる。
  class FakeRunner
    attr_reader :prompts

    def initialize(&responder)
      @responder = responder
      @prompts = []
    end

    def call(prompt, log_path:)
      @prompts << prompt
      command, input, _out, directory = prompt.split(" ")
      @responder.call(command, Rails.root.join(input), Rails.root.join(directory))
    end
  end

  FakeFetcher = Struct.new(:result) do
    def call = result
  end

  SEEDS = %w[種語イチ 種語ニ 種語サン 種語ヨン 種語ゴ 種語ロク].freeze
  # 互いに似ていない、基準以上の読み。
  READINGS = SEEDS.zip(%w[アイウエオカキクケコ サシスセソタチツテト ナニヌネノハヒフヘホ マミムメモヤユヨラリ ルレロワヲンガギグゲ ゴザジズゼゾダヂヅデ]).to_h

  setup do
    @dir = Pathname(Dir.mktmpdir)
    @seeds_path = @dir.join("seeds.txt")
    # 番号・空行・区切り線(---)は種語にしない
    @seeds_path.write(SEEDS.each_with_index.map { |seed, index| "#{index + 1}. #{seed}" }.insert(2, "---").join("\n") + "\n\n")
    write_corpus
    @output = StringIO.new
    @failing = []
    @runner = FakeRunner.new { |command, input, directory| respond(command, input, directory) }
    travel_to Time.zone.local(2026, 11, 13, 3, 0, 0)
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "期限が来たら種語を取り出して run を最後まで通し、次の run は INTERVAL_DAYS 日あとに未使用の種語から始める(force なら期限を見ない)" do
    stub_method(ReadingExtractor, :available?, -> { false }) do
      pipeline.call
      run = runs.sole
      assert_equal ResearchRun::DONE, run.stage
      assert_equal SEEDS.first(ResearchPipeline::SEEDS_PER_RUN), run.seeds.map { |seed| seed["surface"] }
      assert_equal %w[/expand /notation /reading], @runner.prompts.map { |prompt| prompt.split(" ").first }
      assert @runner.prompts.first.end_with?("--auto")
      assert_equal SEEDS.first(ResearchPipeline::SEEDS_PER_RUN).join("\n") + "\n", run.directory.join("register.txt").read

      # 翌日は期限前なので何もしない
      travel 1.day
      pipeline.call
      assert_equal 1, runs.size
      assert_includes @output.string, "新しい run はまだ始めません"

      # INTERVAL_DAYS 日経ったら、残りの種語で始める(時刻が早くても日付で比べる)
      travel_to Time.zone.local(2026, 11, 15, 2, 59, 0)
      pipeline.call
      assert_equal [ SEEDS.last ], runs.last.seeds.map { |seed| seed["surface"] }

      # force なら期限前でも種語を取りに行く(ここでは尽きているので始めない)
      @output.string = +""
      pipeline(force: true).call
      assert_equal 2, runs.size
      assert_includes @output.string, "未使用の種語が残っていません"
      assert_not_includes @output.string, "新しい run はまだ始めません"

      # 種語が尽きたら始めない
      travel ResearchPipeline::INTERVAL_DAYS.days
      pipeline.call
      assert_equal 2, runs.size
    end
  end

  test "公開語・台帳の語と重複する種語は /expand に渡さずに飛ばし、その先の種語で数を満たして、飛ばした語も台帳に記録する" do
    # 種語ニは公開済み(seeds.txt にはひらがなで書いてあっても畳んで当たる)、種語ヨンは前の run で調べた語
    write_corpus("種語ニ")
    @seeds_path.write(@seeds_path.read.sub("種語ニ", "種語に").sub("種語ゴ", "種語ゴ\n種語・ゴ"))
    ResearchLedger.new(@dir.join("auto/ledger.tsv")).append([
      ResearchLedger::Row.new(recorded_on: "2026-11-01", run_id: "20261101-030000", kind: "word", outcome: "rejected", stage: "notation",
                              surface: "種語ヨン", reading: nil, reason: "立項スコアが低い(3)")
    ])

    stub_method(ReadingExtractor, :available?, -> { false }) do
      pipeline(seeds_per_run: 3).call
      run = runs.sole
      # 選んだ種語も照合の相手になる(畳むと種語ゴと同じ「種語・ゴ」は、次の run で飛ばす)
      assert_equal %w[種語イチ 種語サン 種語ゴ], run.seeds.map { |seed| seed["surface"] }
      assert_equal [ [ "種語に", "重複: 表層形が〈種語ニ〉と一致" ], [ "種語ヨン", "重複: 表層形が〈種語ヨン〉と一致" ] ],
                   run.skipped_seeds.map { |seed| seed.values_at("surface", "reason") }
      assert_equal 3, @runner.prompts.first.then { |prompt| Rails.root.join(prompt.split(" ")[1]).readlines.size }
      assert_includes run.directory.join("summary.md").read, "飛ばした種語: 種語に(重複: 表層形が〈種語ニ〉と一致)、種語ヨン"
      assert_includes @output.string, "重複のため飛ばした種語(2 語): 種語に、種語ヨン"
      skipped_rows = ResearchLedger.new(@dir.join("auto/ledger.tsv")).rows.select { |row| row.outcome == "skipped" }
      assert_equal [ [ "seed", run.id ] ], skipped_rows.map { |row| [ row.kind, row.run_id ] }.uniq

      # 次の run は飛ばした語を見直さず、残り(畳むと種語ゴになる語と、種語ロク)から選ぶ
      travel ResearchPipeline::INTERVAL_DAYS.days
      pipeline(seeds_per_run: 3).call
      assert_equal [ "種語ロク" ], runs.last.seeds.map { |seed| seed["surface"] }
      assert_equal [ "種語・ゴ" ], runs.last.skipped_seeds.map { |seed| seed["surface"] }

      # 残りがすべて重複なら run を始めない(記録もしないので、次の起動でまた見る)
      @seeds_path.write("種語イチ\n種語ニ\n")
      travel ResearchPipeline::INTERVAL_DAYS.days
      pipeline.call
      assert_equal 2, runs.size
      assert_includes @output.string, "未使用の種語 1 語は、すべて公開語か台帳の語と重複していました"
    end
  end

  test "段が失敗したらそこで止め、次の起動で期限に関係なく続きから進める" do
    @failing << "/notation"
    stub_method(ReadingExtractor, :available?, -> { false }) do
      pipeline.call
      run = runs.sole
      assert_equal [ "notation", 1 ], [ run.stage, run.attempts ]
      assert_includes @output.string, "notation に失敗しました(1 回目。次の起動でやり直します)"

      @failing.clear
      travel 1.hour
      pipeline.call
      assert_equal ResearchRun::DONE, ResearchRun.load(run.directory).stage
      assert_equal 1, runs.size
    end
  end

  test "公開語の写しが無い・ロックを取れないときは run を始めない" do
    @dir.join("auto/corpus/llms-full.txt").delete
    pipeline(fetcher: FakeFetcher.new(:failed)).call
    assert_empty runs
    assert_includes @output.string, "公開語の写し: failed"
    assert_includes @output.string, "が無いため、run を始めません"

    write_corpus
    @dir.join("auto/.lock").open(File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      pipeline.call
    end
    assert_empty runs
    assert_includes @output.string, "前の起動がまだ動いている"
  end

  test "inbox の注釈の書き出しを /annotation に回し、全語の提案が返らなければ失敗として数えて諦める" do
    inbox = @dir.join("auto/inbox/annotation.json")
    FileUtils.mkdir_p(inbox.dirname)
    inbox.write(JSON.generate("version" => "2", "words" => [ { "word_id" => 7 }, { "word_id" => 8 } ]))
    @seeds_path.write("") # run は始めない

    @failing << "/annotation"
    ResearchRun::MAX_ATTEMPTS.times { pipeline.call }
    assert_not inbox.exist?
    batch = ResearchAnnotationBatch.new(@dir.join("auto/annotation").children.sole)
    assert batch.given_up?
    assert_empty ResearchAnnotationBatch.pending(@dir.join("auto/annotation"))

    inbox.write(JSON.generate("version" => "2", "words" => [ { "word_id" => 9 } ]))
    @failing.clear
    pipeline.call
    assert_includes @output.string, "提案 JSON を書き出しました"
    assert_equal [ 9 ], JSON.parse(@dir.join("auto/annotation").children.max.join("annotation.json").read)["proposals"].map { |p| p["word_id"] }
  end

  private

  def pipeline(fetcher: FakeFetcher.new(:not_modified), force: false, seeds_per_run: ResearchPipeline::SEEDS_PER_RUN)
    ResearchPipeline.new(root: @dir.join("auto"), seeds_path: @seeds_path, runner: @runner, fetcher:, output: @output, force:, seeds_per_run:)
  end

  def runs = ResearchRun.all(@dir.join("auto/runs"))

  def write_corpus(*surfaces)
    path = @dir.join("auto/corpus/llms-full.txt")
    FileUtils.mkdir_p(path.dirname)
    path.write("公開している全 #{surfaces.size} 語の内容を、1ファイルにまとめています。\n" + surfaces.map { |surface| "### #{surface}\n" }.join)
  end

  # 全語を通す応答。@failing に入れたコマンドは何も書かずに失敗する。
  def respond(command, input, directory)
    return false if @failing.include?(command)

    lines = input.extname == ".txt" ? input.readlines(chomp: true) : []
    content = case command
    when "/expand"
      { "seeds" => lines.map { |line| line.match(/\A#(\d+) (.+)\z/) }.map do |m|
        { "id" => m[1].to_i, "confidence" => "high", "candidates" => [ { "surface" => m[2], "reading" => READINGS.fetch(m[2]) } ] }
      end }
    when "/notation"
      { "words" => lines.map { |line| line.match(/\A#(\d+) (.+)\z/) }.map do |m|
        { "id" => m[1].to_i, "input" => m[2], "surface" => m[2], "entry_score" => 5, "confidence" => "high" }
      end }
    when "/reading"
      { "version" => "1", "words" => lines.map { |surface| { "input" => surface, "surface" => surface, "reading" => READINGS.fetch(surface), "alternatives" => [], "confidence" => "high" } } }
    when "/annotation"
      { "proposals" => JSON.parse(input.read)["words"].map { |word| { "word_id" => word["word_id"] } } }
    end
    name = { "/expand" => "expansion.json", "/notation" => "notation.json", "/reading" => "reading.json", "/annotation" => "annotation.json" }.fetch(command)
    directory.join(name).write(JSON.generate(content))
    true
  end
end
