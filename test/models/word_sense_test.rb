require "test_helper"

class WordSenseTest < ActiveSupport::TestCase
  test "reading と word は必須" do
    word_sense = WordSense.new(reading: "")
    assert_not word_sense.valid?
    assert word_sense.errors.added?(:reading, :blank)
    assert word_sense.errors.added?(:word, :blank)
  end

  # 変換の規則そのもの(長音・拗音・撥音など)は値オブジェクトのテスト
  # (RhythmPattern / VowelPattern / MoraCount / LastChar / KanaRing)で押さえる。
  # ここでは保存時に派生値が作られ、読みを変えたら作り直されることだけを見る。
  test "保存時に reading から派生値が作られ、reading を変えると作り直される" do
    word_sense = WordSense.create!(word: words(:abc_murder), reading: "あいうえお")
    assert_equal "aiueo", word_sense.rhythm_pattern
    assert_equal "aiueo", word_sense.vowel_pattern
    assert_equal 5, word_sense.mora_count
    assert_equal "お", word_sense.last_char
    assert_equal 0, word_sense.ring_crossing_count # 五十音の並び順に進むだけなので弦は交差しない

    word_sense.update!(reading: "さつじんじけん")
    assert_equal "satsujinjiken", word_sense.rhythm_pattern
    assert_equal "auiie", word_sense.vowel_pattern
    assert_equal 7, word_sense.mora_count
    assert_equal "ん", word_sense.last_char
    assert_equal 3, word_sense.ring_crossing_count
  end

  test "reading_length / first_char は DB の生成カラムで計算される" do
    word_sense = WordSense.create!(word: words(:abc_murder), reading: "さくら").reload
    assert_equal 3, word_sense.reading_length
    assert_equal "さ", word_sense.first_char
  end

  test "genre は小分類だけを指せる(未指定も可)" do
    assert WordSense.new(word: words(:abc_murder), reading: "さくら", genre: genres(:small_novel)).valid?
    assert WordSense.new(word: words(:abc_murder), reading: "さくら").valid?

    [ genres(:large_literature), genres(:medium_japanese) ].each do |genre|
      word_sense = WordSense.new(word: words(:abc_murder), reading: "さくら", genre: genre)
      assert_not word_sense.valid?, "#{genre.name}(#{genre.level})を指せてしまう"
      assert word_sense.errors.added?(:genre, :must_be_small)
    end
  end

  test "語義を削除すると特徴の中間レコードも消え、マスタは残る" do
    word_sense = word_senses(:murder)
    feature_ids = word_sense.word_sense_features.ids
    assert_not_empty feature_ids

    word_sense.destroy
    assert_empty WordSenseFeature.where(id: feature_ids)
    assert LinguisticFeature.exists?(linguistic_features(:rendaku).id)
  end

  test "語義の更新で親 word の updated_at が進む(touch。Issue 26)" do
    word = words(:abc_murder)
    word.update_column(:updated_at, 1.day.ago)
    before = word.reload.updated_at

    word.word_senses.first.update!(meaning: "更新後の意味")

    assert_operator word.reload.updated_at, :>, before
  end
end
