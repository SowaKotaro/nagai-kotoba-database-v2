require "test_helper"

class WordSenseMetricsTest < ActiveSupport::TestCase
  # フィクスチャの語: ABC殺人事件(読み さつじんじけん・特徴2件)/ カレーライス(読み カレー・別表記1件)。
  # test_helper の setup が読み込み直後に refresh! を掛けている。

  test "語義から代表値を焼き込む" do
    word = words(:abc_murder).reload
    assert_equal 1, word.sense_count
    assert_equal 7, word.min_reading_length
    assert_equal 7, word.max_reading_length
    assert_equal 7, word.max_mora_count
    assert_equal 3, word.max_ring_crossing_count
    assert_equal 3, word.min_ring_crossing_count
    assert_equal "さつじんじけん", word.min_reading
    assert_equal "さつじんじけん", word.max_reading
    assert_equal "んけじんじつさ", word.min_reversed_reading
  end

  test "別表記と特徴の数を数える" do
    assert_equal 2, words(:abc_murder).reload.feature_count
    assert_equal 0, words(:abc_murder).reload.variant_count
    assert_equal 1, words(:curry).reload.variant_count
    assert_equal 0, words(:curry).reload.feature_count
  end

  test "小書きのかな・長音符・濁点は清濁と小書きを区別して数える" do
    # イックションペカットゥーヂャ
    #   小書き ッ ョ ッ ゥ ャ = 5 / 長音符 ー = 1 / 濁点・半濁点 ペ ヂ = 2
    # 照合順序(as_ci)のままだと ッ=ツ・ペ=ヘ に畳まれて数を取り違えるため、
    # 集計は utf8mb4_bin へ落として数えている。その退行防止。
    word = Word.create!(surface: "小書き検証語")
    word.word_senses.create!(reading: "イックションペカットゥーヂャ")

    word.reload
    assert_equal 5, word.max_small_kana_count
    assert_equal 1, word.max_chouon_count
    assert_equal 2, word.max_dakuten_count
  end

  test "表層形由来の値は生成カラムで自動追従する" do
    word = Word.create!(surface: "あいう")
    word.word_senses.create!(reading: "アイウエオカ")

    word.reload
    assert_equal 3, word.surface_length
    # 読み6字 / 表記3字 = 2.0
    assert_equal 2.0, word.reading_density.to_f

    word.update!(surface: "あいうえおか")
    assert_equal 6, word.reload.surface_length
    assert_equal 1.0, word.reading_density.to_f
  end

  test "語義が複数なら最小と最大を分けて持つ" do
    word = words(:abc_murder)
    word.word_senses.create!(reading: "アイウエオカキクケコサシ")

    word.reload
    assert_equal 2, word.sense_count
    assert_equal 7, word.min_reading_length
    assert_equal 12, word.max_reading_length
    # 照合順序(as_ci)はひらがな⇔カタカナを同一視するので、あ行の「アイウエオ…」が
    # さ行の「さつじんじけん」より前に来る。
    assert_equal "アイウエオカキクケコサシ", word.min_reading
    assert_equal "さつじんじけん", word.max_reading
  end

  test "語義を消したら代表値も戻る" do
    word = words(:curry)
    word.word_senses.first.destroy!

    word.reload
    assert_equal 0, word.sense_count
    assert_nil word.max_reading_length
    assert_nil word.min_reading
    # 別表記は語義とともに消えるので 0 に戻る
    assert_equal 0, word.variant_count
  end

  test "特徴を消したら feature_count が減る" do
    word = words(:abc_murder)
    word_sense_features(:murder_rendaku).destroy!

    assert_equal 1, word.reload.feature_count
  end

  test "語義が1つも無い語は件数が0・指標は NULL" do
    word = Word.create!(surface: "語義なしの語")

    word.reload
    assert_equal 0, word.sense_count
    assert_equal 0, word.variant_count
    assert_equal 0, word.feature_count
    assert_nil word.max_reading_length
    assert_nil word.reading_density
  end

  test "refresh! は冪等で、直接 SQL で崩した値も戻せる" do
    word = words(:abc_murder)
    word.update_columns(max_reading_length: 999, sense_count: 42)

    WordSenseMetrics.refresh!
    word.reload
    assert_equal 7, word.max_reading_length
    assert_equal 1, word.sense_count
  end

  test "焼き直しで updated_at は進めない(ETag とキャッシュを無駄に失効させない)" do
    word = words(:abc_murder)
    before = word.updated_at

    WordSenseMetrics.refresh!([ word.id ])
    assert_equal before.to_i, word.reload.updated_at.to_i
  end

  test "id を渡した焼き直しは他の語に触らない" do
    other = words(:curry)
    other.update_columns(sense_count: 42)

    WordSenseMetrics.refresh!([ words(:abc_murder).id ])
    assert_equal 42, other.reload.sense_count
  end
end
