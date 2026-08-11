require "test_helper"

class MorphemeFrequenciesTest < ActiveSupport::TestCase
  setup { MorphemeFrequencies.path = nil }
  teardown { MorphemeFrequencies.path = nil }

  # 実ファイルを書き換えずに、任意の集計内容で読ませる。
  def with_counts(counts, word_count: 100)
    payload = {
      "metadata" => { "generated_at" => Time.current.iso8601, "word_count" => word_count },
      "counts" => counts
    }
    file = Tempfile.new([ "morpheme_frequencies", ".json" ])
    file.write(JSON.generate(payload))
    file.close
    MorphemeFrequencies.path = file.path
    yield
  ensure
    MorphemeFrequencies.path = nil
    file&.unlink
  end

  test "頻度の多い順に並ぶ" do
    with_counts({ "少ない" => 3, "多い" => 10, "中くらい" => 5 }) do
      assert_equal %w[多い 中くらい 少ない], MorphemeFrequencies.entries.map(&:text)
    end
  end

  test "最頻が weight 1.0・最少が 0.0 になる" do
    with_counts({ "多い" => 10, "中くらい" => 5, "少ない" => 2 }) do
      entries = MorphemeFrequencies.entries
      assert_in_delta 1.0, entries.first.weight, 0.001
      assert_in_delta 0.0, entries.last.weight, 0.001
      assert entries.first.top?
      assert_not entries.last.top?
    end
  end

  test "全部同じ頻度なら一律で最大の級数にする" do
    with_counts({ "あああ" => 4, "いいい" => 4 }) do
      assert MorphemeFrequencies.entries.all? { |entry| entry.weight == 1.0 }
    end
  end

  test "出現が1回だけの形態素は載せない" do
    with_counts({ "二回以上" => 2, "一回だけ" => 1 }) do
      assert_equal [ "二回以上" ], MorphemeFrequencies.entries.map(&:text)
    end
  end

  test "表示件数の上限で打ち切る" do
    counts = (1..(MorphemeFrequencies::DISPLAY_LIMIT + 20)).to_h { |i| [ "語#{i}", i + 1 ] }
    with_counts(counts) do
      assert_equal MorphemeFrequencies::DISPLAY_LIMIT, MorphemeFrequencies.entries.size
    end
  end

  test "集計ファイルが無ければ空になり、available? が false" do
    MorphemeFrequencies.path = Rails.root.join("db/does_not_exist.json")
    assert_empty MorphemeFrequencies.entries
    assert_not MorphemeFrequencies.available?
  ensure
    MorphemeFrequencies.path = nil
  end

  test "壊れた JSON でも例外にせず空として扱う" do
    file = Tempfile.new([ "broken", ".json" ])
    file.write("{ これは JSON ではない")
    file.close
    MorphemeFrequencies.path = file.path
    assert_empty MorphemeFrequencies.entries
  ensure
    MorphemeFrequencies.path = nil
    file&.unlink
  end

  test "リポジトリに入っている集計ファイルが読める" do
    assert MorphemeFrequencies.available?, "db/morpheme_frequencies.json が読めていない"
    assert MorphemeFrequencies.entries.all? { |entry| entry.count >= MorphemeFrequencies::MIN_COUNT }
    assert MorphemeFrequencies.entries.all? { |entry| entry.text.length >= 2 }
    assert_equal 1, MorphemeFrequencies.entries.count(&:top?), "朱にする最頻は1件だけ"
  end
end
