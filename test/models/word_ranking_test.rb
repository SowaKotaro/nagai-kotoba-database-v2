require "test_helper"

class WordRankingTest < ActiveSupport::TestCase
  # フィクスチャの公開語は ABC殺人事件(さつじんじけん) と カレーライス(カレー) の2語。
  def board(key)
    WordRanking.all.find { |ranking| ranking.key == key }
  end

  test "枠は WordSort のランキング用の並びから作り、順位表に出さない並びは除く" do
    assert_empty WordRanking.all.map(&:key) - WordSort::RANKING_KEYS

    # 順位表として出さない並びは枠にしない
    # 別表記の多さは一覧の並び替えとしては残すが、ランキングページには出さない(オーナー判断)。
    assert_includes WordSort::RANKING_KEYS, "variant_count_desc"
    assert_nil board("variant_count_desc")

    # 組を並べる向き(キーの末尾)は、WordSort の並びの先頭(指標の向き)と食い違わない
    WordRanking.all.each do |ranking|
      direction = ranking.ascending? ? "ASC" : "DESC"
      metric = WordSort::RANKING_METRICS.fetch(ranking.key)
      assert WordSort::RANKING_ORDERS.fetch(ranking.key).start_with?("words.#{metric} #{direction}"), ranking.key
    end
  end

  test "各枠の値と並び(フィクスチャの2語)" do
    groups = board("length_desc").groups
    assert_equal [ "ABC殺人事件", "カレーライス" ], groups.map { |group| group[:representative][:surface] }
    assert_equal [ 1, 2 ], groups.map { |group| group[:rank] }
    assert_equal [ 7, 3 ], groups.map { |group| group[:value] }
    assert_equal [ "さつじんじけん" ], groups.first[:representative][:readings]

    # 一字あたりの読みの長さは小数で丸める
    groups = board("reading_density_desc").groups
    # ABC殺人事件 = 表記7字 / 読み7字 → 1.0、カレーライス = 表記6字 / 読み3字 → 0.5
    assert_equal [ 1.0, 0.5 ], groups.map { |group| group[:value] }
    assert board("reading_density_desc").decimal?

    # 濁点の数は清濁を区別して数える
    # さつじんじけん の「じ」2つだけが該当し、濁点の無い カレー は下限未満で載らない
    assert_equal [ [ "ABC殺人事件", 2 ] ], surfaces_and_values(board("dakuten_desc"))

    # 長音符・特徴の枠は該当語だけを載せる
    assert_equal [ [ "カレーライス", 1 ] ], surfaces_and_values(board("chouon_desc"))
    assert_equal [ [ "ABC殺人事件", 2 ] ], surfaces_and_values(board("feature_count_desc"))

    # 下限に満たない語しかない枠は空になる
    # フィクスチャの読みはどちらも小書きのかなを含まず、語義はどちらも1つだけ。
    assert_empty board("small_kana_desc").groups
    assert_empty board("sense_count_desc").groups

    # 円環の交差が多い順は交差する語だけを載せる
    # さつじんじけん は 3 回交差する。カレー は弦が 1 本しかなく交差 0 回なので下限未満。
    assert_equal [ [ "ABC殺人事件", 3 ] ], surfaces_and_values(board("ring_crossing_desc"))

    # 未注釈の語は代表にも畳む語にも載せない
    words = WordRanking.all.flat_map(&:groups).flat_map { |group| [ group[:representative], *group[:others] ] }
    assert_not_includes words.map { |word| word[:surface] }, "バミューダトライアングル"

    # 拗音・促音は促音「ッ」も含めて小書きのかなを1字ずつ数える
    # 「文字数 - 拍数」では促音・長音が独立した拍のため現れない。小書きを直接数えて
    # ッ ョ ッ ゥ ャ の 5 個になることを担保する(退行防止)。
    create_published_word(surface: "小書き検証語", reading: "イックションペカットゥーヂャ")
    assert_equal [ [ "小書き検証語", 5 ] ], surfaces_and_values(board("small_kana_desc"))
  end

  test "同じ値の語は読みがいちばん長い語を代表に1組にまとめ、順位は組ごとに1から振る" do
    # 円環の交差が少ない順: 交差 0 回の2語(読み10字 と カレー3字)が1組で、長い方が代表。
    # 交差 3 回の さつじんじけん は、上の組が2語でも 2 位(語数で順位を飛ばさない)
    create_published_word(surface: "五十音順の長い語", reading: "あいうえおかきくけこ")
    groups = board("ring_crossing_asc").groups
    assert_equal [ [ 1, 0, 2 ], [ 2, 3, 1 ] ], groups.map { |group| group.values_at(:rank, :value, :count) }
    assert_equal "五十音順の長い語", groups.first[:representative][:surface]
    assert_equal [ "カレーライス" ], groups.first[:others].map { |word| word[:surface] }
    assert_empty groups.last[:others]

    # 比率は表示(小数 DECIMAL_PLACES 桁)が同じなら1組にする。読み37字 / 表記14字 = 2.6429 と 読み29字 / 表記11字 = 2.6364 は、どちらも 2.64
    create_published_word(surface: "比" * 14, reading: "ア" * 37)
    create_published_word(surface: "率" * 11, reading: "ア" * 29)
    group = board("reading_density_desc").groups.first
    assert_equal [ 1, 2.64, 2 ], group.values_at(:rank, :value, :count)
    assert_equal "比" * 14, group[:representative][:surface]

    # 畳む語は FOLD_LIMIT 語まで。読みの短い語から外れ、組の語数(count)は外れた語も数える
    # 長音符 1 本の組: カレー(3字) と、読み 6 字から 1 字ずつ長くした FOLD_LIMIT + 1 語
    (WordRanking::FOLD_LIMIT + 1).times do |i|
      create_published_word(surface: "長音の組#{i}", reading: "ナ" * (5 + i) + "ー")
    end
    group = board("chouon_desc").groups.first
    assert_equal WordRanking::FOLD_LIMIT + 2, group[:count]
    assert_equal "長音の組#{WordRanking::FOLD_LIMIT}", group[:representative][:surface]
    assert_equal WordRanking::FOLD_LIMIT, group[:others].size
    assert_not_includes group[:others].map { |word| word[:surface] }, "カレーライス"
  end

  test "ページに出す順位表は、該当語が TOP_LIMIT 件を超えた枠だけ、値の違う上位 TOP_LIMIT 組を並べる" do
    ranking = board("length_desc")
    assert_empty ranking.board, "2語しか無いうちは順位表にしない"

    publish_words(WordRanking::TOP_LIMIT - 2) # 公開語をちょうど TOP_LIMIT 件にする
    assert_empty ranking.board, "ちょうど TOP_LIMIT 件でも順位表にしない"

    publish_words(2, offset: WordRanking::TOP_LIMIT)
    # 読みの長さは 16・15・12〜8・7(さつじんじけん と 母集団2 の2語)・6・5・3 字の 11 通り。上から 10 通りを 1〜10 位にし、3 字(カレー)は載せない
    groups = ranking.board
    assert_equal (1..WordRanking::TOP_LIMIT).to_a, groups.map { |group| group[:rank] }
    assert_equal [ 16, 15, 12, 11, 10, 9, 8, 7, 6, 5 ], groups.map { |group| group[:value] }
    # offset は上の組の語数の合計(7 字の組が2語なので、6 字の組から 1 つずれる)
    assert_equal [ 0, 1, 2, 3, 4, 5, 6, 7, 9, 10 ], groups.map { |group| group[:offset] }
  end

  private

  # 枠の組ごとの [代表の見出し語, 値]
  def surfaces_and_values(ranking)
    ranking.groups.map { |group| [ group[:representative][:surface], group[:value] ] }
  end

  # 濁点・小書き・長音を含まない読みの公開語を count 語つくる
  def publish_words(count, offset: 0)
    count.times do |i|
      create_published_word(surface: "順位の母集団#{offset + i}", reading: "ナナナナナ" + "ア" * (offset + i))
    end
  end
end
