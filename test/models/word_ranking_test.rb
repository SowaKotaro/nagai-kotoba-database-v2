require "test_helper"

class WordRankingTest < ActiveSupport::TestCase
  # フィクスチャの公開語は ABC殺人事件(さつじんじけん) と カレーライス(カレー) の2語。
  def board(key)
    WordRanking.all.find { |ranking| ranking.key == key }
  end

  test "すべての枠が WordSort のランキング用の並びと対応する" do
    assert_empty WordRanking.all.map(&:key) - WordSort::RANKING_KEYS
  end

  test "順位表として出さない並びは枠にしない" do
    # 別表記の多さは一覧の並び替えとしては残すが、ランキングページには出さない(オーナー判断)。
    assert_includes WordSort::RANKING_KEYS, "variant_count_desc"
    assert_nil board("variant_count_desc")
  end

  test "読みが長い順は最長の語が先頭で、値は読みの文字数" do
    rows = board("length_desc").top
    assert_equal [ "ABC殺人事件", "カレーライス" ], rows.map { |row| row[:surface] }
    assert_equal [ 1, 2 ], rows.map { |row| row[:rank] }
    assert_equal [ 7, 3 ], rows.map { |row| row[:value] }
    assert_equal [ "さつじんじけん" ], rows.first[:readings]
  end

  test "一字あたりの読みの長さは小数で丸める" do
    rows = board("reading_density_desc").top
    # ABC殺人事件 = 表記7字 / 読み7字 → 1.0、カレーライス = 表記6字 / 読み3字 → 0.5
    assert_equal [ 1.0, 0.5 ], rows.map { |row| row[:value] }
    assert board("reading_density_desc").decimal?
  end

  test "濁点の数は清濁を区別して数える" do
    rows = board("dakuten_desc").top
    # さつじんじけん の「じ」2つだけが該当し、濁点の無い カレー は下限未満で載らない
    assert_equal [ "ABC殺人事件" ], rows.map { |row| row[:surface] }
    assert_equal 2, rows.first[:value]
  end

  test "長音符・特徴の枠は該当語だけを載せる" do
    assert_equal [ [ "カレーライス", 1 ] ], board("chouon_desc").top.map { |row| [ row[:surface], row[:value] ] }
    assert_equal [ [ "ABC殺人事件", 2 ] ], board("feature_count_desc").top.map { |row| [ row[:surface], row[:value] ] }
  end

  test "下限に満たない語しかない枠は空になる" do
    # フィクスチャの読みはどちらも小書きのかなを含まず、語義はどちらも1つだけ。
    assert_empty board("small_kana_desc").top
    assert_empty board("sense_count_desc").top
  end

  test "拗音・促音は促音「ッ」も含めて小書きのかなを1字ずつ数える" do
    # 「文字数 - 拍数」では促音・長音が独立した拍のため現れない。小書きを直接数えて
    # ッ ョ ッ ゥ ャ の 5 個になることを担保する(退行防止)。
    word = Word.create!(surface: "小書き検証語", annotated_at: Time.current)
    word.word_senses.create!(reading: "イックションペカットゥーヂャ")

    row = board("small_kana_desc").top.find { |candidate| candidate[:id] == word.id }
    assert_equal 5, row[:value]
  end

  test "円環の交差が多い順は交差する語だけを載せる" do
    rows = board("ring_crossing_desc").top
    # さつじんじけん は 3 回交差する。カレー は弦が 1 本しかなく交差 0 回なので下限未満。
    assert_equal [ [ "ABC殺人事件", 3 ] ], rows.map { |row| [ row[:surface], row[:value] ] }
  end

  test "円環の交差が少ない順は交差 0 回の語も載せ、同値なら読みが長い語を上位にする" do
    zero_long = Word.create!(surface: "五十音順の長い語", annotated_at: Time.current)
    zero_long.word_senses.create!(reading: "あいうえおかきくけこ")

    rows = board("ring_crossing_asc").top
    # 交差 0 回が2語(読み10字 と カレー3字)並び、長い方が先。次に交差 3 回の さつじんじけん。
    assert_equal [ "五十音順の長い語", "カレーライス", "ABC殺人事件" ], rows.map { |row| row[:surface] }
    assert_equal [ 0, 0, 3 ], rows.map { |row| row[:value] }
    assert_equal [ 1, 1, 3 ], rows.map { |row| row[:rank] }
  end

  test "未注釈の語は載せない" do
    surfaces = WordRanking.all.flat_map { |ranking| ranking.top.map { |row| row[:surface] } }
    assert_not_includes surfaces, "バミューダトライアングル"
  end

  test "同じ値の語は同順位になり、その分だけ次の順位を飛ばす" do
    words = [ { value: 5 }, { value: 5 }, { value: 3 } ]
    ranks = board("length_desc").send(:with_ranks, words).map { |row| row[:rank] }
    assert_equal [ 1, 1, 3 ], ranks
  end

  test "上位の件数は limit で絞れる" do
    assert_equal 1, board("length_desc").top(limit: 1).size
  end
end
