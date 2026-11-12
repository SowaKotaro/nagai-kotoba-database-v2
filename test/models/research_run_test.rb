require "test_helper"

class ResearchRunTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir)
    @ledger = ResearchLedger.new(@dir.join("ledger.tsv"))
    travel_to Time.zone.local(2026, 11, 13, 3, 0, 0)
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "3 つの段を通し、確実でない語・読みが短い語・重複を却下して、一括登録に貼る 2 つを作る" do
    known = [ [ "帝黒アレキサンダーズ", "テイコクアレキサンダーズ" ] ]
    run = ResearchRun.create(@dir.join("runs"), seeds: %w[泥門デビルバッツ 初恋クレイジー], corpus_fetched_at: nil, ledger: @ledger)
    assert_equal [ "泥門デビルバッツ", "初恋クレイジー" ], @ledger.used_seeds.to_a

    stub_method(ReadingExtractor, :available?, -> { false }) do
      # expand: 入力は「#ID 種語」
      run.write_input
      assert_equal "#1 泥門デビルバッツ\n#2 初恋クレイジー\n", run.input_path.read
      assert_not run.absorb(json("seeds" => [ { "id" => 1 } ]), known:, ledger: @ledger), "種語 2 が返っていなければ読めなかった扱い"
      assert_equal "expand", run.stage

      candidates = {
        "泥門デビルバッツ" => "デイモンデビルバッツ", "白秋ダイナソアーズ" => "ハクシュウダイナソアーズ",
        "神龍寺ナーガ" => "シンリュウジナーガ", "帝黒アレキサンダーズ" => "テイコクアレキサンダーズ",
        "白秋ダイナソアー" => "ハクシュウダイナソアー", "王城ホワイトナイツ" => "オウジョウホワイトナイツ",
        "巨深ポセイドンズ" => "キョシンポセイドンズ", "賊学カメレオンズ" => "ゾクガクカメレオンズ",
        "西部ワイルドガンマンズ" => "セイブワイルドガンマンズ", "柱谷ディアーズ" => "ハシラタニディアーズ"
      }.map { |surface, reading| { "surface" => surface, "reading" => reading } }
      assert run.absorb(json("seeds" => [
        { "id" => 1, "confidence" => "high", "words" => candidates.map { |c| c["surface"] }, "candidates" => candidates },
        { "id" => 2, "confidence" => "medium", "candidates" => [ { "surface" => "初恋クレイジーズ", "reading" => "ハツコイクレイジーズ" } ] }
      ]), known:, ledger: @ledger)
      assert_equal "notation", run.stage
      assert_equal %w[泥門デビルバッツ 白秋ダイナソアーズ 王城ホワイトナイツ 巨深ポセイドンズ 賊学カメレオンズ 西部ワイルドガンマンズ 柱谷ディアーズ],
                   run.words.map { |word| word["surface"] }

      # notation: 入力は「#ID 表層形」。満点・high・分割案なしだけを通し、確定した表記に置き換える
      run.write_input
      ids = run.words.to_h { |word| [ word["surface"], word["id"] ] }
      assert_equal "##{ids["泥門デビルバッツ"]} 泥門デビルバッツ", run.input_path.readlines.first.chomp
      notation = ->(surface, score, confidence, **extra) {
        { "id" => ids.fetch(surface), "input" => surface, "surface" => surface, "entry_score" => score, "confidence" => confidence }.merge(extra.transform_keys(&:to_s))
      }
      assert run.absorb(json("words" => [
        notation.call("泥門デビルバッツ", 5, "high"), notation.call("白秋ダイナソアーズ", 4, "high"),
        notation.call("王城ホワイトナイツ", 5, "high", split: %w[王城 ホワイトナイツ]), notation.call("巨深ポセイドンズ", 5, "high"),
        notation.call("賊学カメレオンズ", 5, "high"), notation.call("西部ワイルドガンマンズ", 5, "high").merge("surface" => "西部ワイルド・ガンマンズ"),
        notation.call("柱谷ディアーズ", 5, "medium")
      ]), known:, ledger: @ledger)

      # reading: 入力は表層形だけ。high で読みが揺れない語だけを通す
      run.write_input
      assert_equal "泥門デビルバッツ\n巨深ポセイドンズ\n賊学カメレオンズ\n西部ワイルド・ガンマンズ\n", run.input_path.read
      reading = ->(surface, reading, confidence, alternatives = []) {
        { "input" => surface, "surface" => surface, "reading" => reading, "alternatives" => alternatives, "confidence" => confidence }
      }
      assert run.absorb(json("version" => "1", "words" => [
        reading.call("泥門デビルバッツ", "デイモンデビルバッツ", "high"), reading.call("巨深ポセイドンズ", "キョシンポセイドンズ", "medium"),
        reading.call("賊学カメレオンズ", "ゾクガクカメレオンズ", "high", [ "ゾッガクカメレオンズ" ]),
        reading.call("西部ワイルド・ガンマンズ", "セイブワイルドガンマンズ", "high")
      ]), known:, ledger: @ledger)
    end

    assert_equal ResearchRun::DONE, run.stage
    assert run.finished?
    assert_equal "泥門デビルバッツ\n西部ワイルド・ガンマンズ\n", run.directory.join("register.txt").read
    assert_equal [ "泥門デビルバッツ", "西部ワイルド・ガンマンズ" ],
                 JSON.parse(run.directory.join("reading.json").read)["words"].map { |word| word["input"] }

    rejected = run.directory.join("rejected.tsv").readlines(chomp: true).map { |line| line.split("\t").values_at(0, 1, 3) }
    assert_equal [
      [ "expand", "神龍寺ナーガ", "読みが基準に届かない(シンリュウジナーガ 9字)" ],
      [ "expand", "帝黒アレキサンダーズ", "重複: 表層形が〈帝黒アレキサンダーズ〉と一致" ],
      [ "expand", "白秋ダイナソアー", "重複: 読みが〈白秋ダイナソアーズ〉(ハクシュウダイナソアーズ)と似ている" ],
      [ "expand", "初恋クレイジーズ", "系統の確信度が high でない(medium)" ],
      [ "notation", "白秋ダイナソアーズ", "立項スコアが満点でない(4)" ],
      [ "notation", "王城ホワイトナイツ", "分割案あり(王城 / ホワイトナイツ)" ],
      [ "notation", "柱谷ディアーズ", "確信度が high でない(medium)" ],
      [ "reading", "巨深ポセイドンズ", "確信度が high でない(medium)" ],
      [ "reading", "賊学カメレオンズ", "読みが揺れる(ゾッガクカメレオンズ)" ]
    ], rejected

    # 台帳: 種語 2・却下 9・登録用に出した 2。却下した語も、次の run の照合の相手になる
    assert_equal({ "seed" => 2, "word" => 11 }, @ledger.rows.map(&:kind).tally)
    assert_equal({ "used" => 2, "rejected" => 9, "output" => 2 }, @ledger.rows.map(&:outcome).tally)
    assert_includes @ledger.known_words, [ "西部ワイルド・ガンマンズ", "セイブワイルドガンマンズ" ]

    summary = run.directory.join("summary.md").read
    assert_includes summary, "## expand: 11 語 → 通過 7 語"
    assert_includes summary, "- 却下 重複: 2 語"
    assert_includes summary, "step1 に register.txt"
  end

  test "読めない出力は段を進めず、同じ段で MAX_ATTEMPTS 回失敗したら run を止める" do
    run = ResearchRun.create(@dir.join("runs"), seeds: %w[種語], corpus_fetched_at: nil, ledger: @ledger)

    assert_not run.absorb("壊れた JSON", known: [], ledger: @ledger)
    (ResearchRun::MAX_ATTEMPTS - 1).times { run.record_failure }
    assert_equal "expand", ResearchRun.load(run.directory).stage

    run.record_failure
    reloaded = ResearchRun.load(run.directory)
    assert_equal [ ResearchRun::ABORTED, ResearchRun::MAX_ATTEMPTS ], [ reloaded.stage, reloaded.attempts ]
    assert reloaded.finished?
  end

  private

  def json(hash) = JSON.generate(hash)
end
