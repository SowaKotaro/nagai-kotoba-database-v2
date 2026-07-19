require "test_helper"

# 統計ページの集計(docs/stats.md)。公開対象は fixtures の
# ABC殺人事件(読み さつじんじけん)とカレーライス(読み カレー)の2語・2語義。
class SiteStatisticsTest < ActiveSupport::TestCase
  setup do
    @stats = SiteStatistics.new
  end

  test "規模: 公開中の語・語義・別表記・のべ読み文字を数える(未注釈は含めない)" do
    assert_equal 2, @stats.scale[:words]
    assert_equal 2, @stats.scale[:senses]
    assert_equal 1, @stats.scale[:variants]
    assert_equal 0, @stats.scale[:homophone_groups]
    assert_equal 10, @stats.scale[:total_reading_chars] # 7 + 3
  end

  test "読みの長さ: 平均・中央値・最頻(同数なら短い方)・最長・平均モーラ" do
    assert_in_delta 5.0, @stats.reading_length[:average]
    assert_in_delta 5.0, @stats.reading_length[:median]
    assert_equal 3, @stats.reading_length[:mode]
    assert_equal 7, @stats.reading_length[:max]
    assert_in_delta 5.0, @stats.reading_length[:average_mora]
  end

  test "同音異義の組: 同じ読みの語義が2つ以上ある読みを数える" do
    word = Word.create!(surface: "撮つ人事件", annotated_at: Time.current, annotation_status: :done)
    word.word_senses.create!(reading: "さつじんじけん")

    assert_equal 1, SiteStatistics.new.scale[:homophone_groups]
  end

  test "文字と音: 頭文字・末尾文字のカバレッジと文字種の割合" do
    assert_equal 2, @stats.letters[:first_char_kinds] # さ→サ, カ
    assert_equal 2, @stats.letters[:last_char_kinds]  # ん→ン, レ
    assert_equal 46, @stats.letters[:kana_total]
    assert_in_delta 50.0, @stats.letters[:katakana_only_pct] # カレーライス
    assert_in_delta 50.0, @stats.letters[:with_kanji_pct]    # ABC殺人事件
    assert_in_delta 50.0, @stats.letters[:with_chouon_pct]   # カレー
  end

  test "50音ヒートマップ用の頭文字・末尾文字はカタカナへ正規化して数える" do
    assert_equal({ "サ" => 1, "カ" => 1 }, @stats.first_char_counts) # さ→サ
    assert_equal({ "ン" => 1, "レ" => 1 }, @stats.last_char_counts)  # ん→ン
  end

  test "行×行マトリクス: 頭文字と末尾文字を行に畳んで数える" do
    matrix = @stats.sound_matrix
    assert_equal 1, matrix[:cells][[ "サ", "ン" ]] # さつじんじけん
    assert_equal 1, matrix[:cells][[ "カ", "ラ" ]] # カレー
    assert_equal 1, matrix[:max_count]
  end

  test "長さの分布は最小〜最大を0件も含めて埋める" do
    values = @stats.reading_length_distribution.map { |bin| bin[:value] }
    counts = @stats.reading_length_distribution.map { |bin| bin[:count] }
    assert_equal (3..7).to_a, values
    assert_equal [ 1, 0, 0, 0, 1 ], counts
  end

  test "長さの分布は30以上をまとめ棒(overflow)1本に畳む" do
    [ 32, 40 ].each_with_index do |length, index|
      word = Word.create!(surface: "長い開発語#{index}", annotated_at: Time.current, annotation_status: :done)
      word.word_senses.create!(reading: "ナ" * length)
    end

    distribution = SiteStatistics.new.reading_length_distribution
    assert_equal (3..29).to_a + [ 30 ], distribution.map { |bin| bin[:value] }
    overflow = distribution.last
    assert overflow[:overflow]
    assert_equal 2, overflow[:count]   # 32文字 + 40文字
    # まとめ棒より手前(30未満)には overflow を立てない
    assert distribution[0..-2].none? { |bin| bin[:overflow] }
  end

  test "推移: 週ごとの新収録と累計を開帳の週から並べる" do
    timeline = @stats.timeline
    assert_equal 2, timeline.last[:cumulative]
    assert_equal @stats.word_count, timeline.sum { |week| week[:count] }
    # 週の並びは古い順で欠番なし(7日刻み)
    timeline.each_cons(2) do |previous, following|
      assert_equal previous[:start_on] + 7, following[:start_on]
    end
  end

  test "ジャンル別の語義数: 大→中→小の3階層に語義数を集約する(サンバースト用)" do
    map = @stats.genre_map
    assert_equal 1, map[:covered]
    large = map[:groups].sole
    assert_equal [ "文学", 1 ], [ large[:name], large[:count] ]
    medium = large[:children].sole
    assert_equal [ "日本文学", 1 ], [ medium[:name], medium[:count] ]
    small = medium[:children].sole
    assert_equal [ "小説", 1 ], [ small[:name], small[:count] ]
  end

  test "語種: 単一語種はその名前、複数語種は混種語として数え、ワッフルは100マスに配分する" do
    word_senses(:curry).word_sense_origins.create!(word_origin: word_origins(:wago))

    origins = SiteStatistics.new.origins
    assert_equal 2, origins[:covered]
    names = origins[:categories].map { |category| category[:name] }
    assert_includes names, SiteStatistics::MIXED_ORIGIN # カレー = 英語 + 和語
    assert_includes names, "漢語"                       # 殺人事件
    assert_equal 100, origins[:categories].sum { |category| category[:cells] }
  end

  test "エンティティ型: 付与された型を件数つきで多い順に返す" do
    assert_equal [ { id: entity_types(:book_title).id, name: "書籍名", count: 1 } ], @stats.entity_types
  end

  test "母音スペクトル: 拍位置ごとの母音構成(auiie / aee)" do
    spectrum = @stats.vowel_spectrum
    assert_equal 2, spectrum[:total]
    first = spectrum[:positions].first
    assert_equal 1, first[:position]
    assert_equal({ "a" => 2 }, first[:counts])
    # 2語義とも母音は5拍未満で尽きる(最長 auiie の5拍まで)
    assert_equal 5, spectrum[:positions].last[:position]
  end

  test "頭の子音: 第1拍の子音ごとに頭文字を束ねる" do
    consonants = @stats.head_consonants.index_by { |group| group[:consonant] }
    assert_equal 1, consonants["s"][:count]
    assert_equal [ "サ" ], consonants["s"][:chars] # 頭文字はカタカナへ正規化済み
    assert_equal 1, consonants["k"][:count]
    assert_equal [ "カ" ], consonants["k"][:chars]
  end

  test "特徴ランキング: 件数と該当部分つきの実例を返す" do
    ranking = @stats.feature_ranking
    assert_equal 2, ranking[:total]
    rendaku = ranking[:rows].find { |row| row[:name] == "連濁" }
    assert_equal 1, rendaku[:count]
    assert_equal({ surface: "ABC殺人事件", target: "殺人", target_start: 3 }, rendaku[:example])
  end

  test "未注釈の語だけなら数字はゼロで空の構造を返す(例外を出さない)" do
    Word.annotated.destroy_all

    stats = SiteStatistics.new
    assert_equal 0, stats.word_count
    assert_empty stats.timeline
    assert_empty stats.reading_length_distribution
    assert_equal 0, stats.sound_matrix[:max_count]
    assert_empty stats.genre_map[:groups]
    assert_empty stats.origins[:categories]
    assert_empty stats.vowel_spectrum[:positions]
    assert_empty stats.head_consonants
    assert_empty stats.feature_ranking[:rows]
  end
end
