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

  test "期限が来たら種語を取り出して run を最後まで通し、次の run は INTERVAL_DAYS 日あとに未使用の種語から始める" do
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

      # 種語が尽きたら始めない
      travel ResearchPipeline::INTERVAL_DAYS.days
      pipeline.call
      assert_equal 2, runs.size
      assert_includes @output.string, "未使用の種語が残っていません"
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

  def pipeline(fetcher: FakeFetcher.new(:not_modified))
    ResearchPipeline.new(root: @dir.join("auto"), seeds_path: @seeds_path, runner: @runner, fetcher:, output: @output)
  end

  def runs = ResearchRun.all(@dir.join("auto/runs"))

  def write_corpus
    path = @dir.join("auto/corpus/llms-full.txt")
    FileUtils.mkdir_p(path.dirname)
    path.write("公開している全 0 語の内容を、1ファイルにまとめています。\n")
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
