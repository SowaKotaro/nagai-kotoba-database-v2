require "test_helper"

class WordSenseTest < ActiveSupport::TestCase
  test "reading が空だと無効" do
    word_sense = WordSense.new(word: words(:abc_murder), reading: "")
    assert_not word_sense.valid?
    assert word_sense.errors.added?(:reading, :blank)
  end

  test "word が無いと無効" do
    word_sense = WordSense.new(reading: "さくら")
    assert_not word_sense.valid?
    assert word_sense.errors.added?(:word, :blank)
  end

  test "保存時に reading から rhythm_pattern が自動生成される" do
    word_sense = WordSense.create!(word: words(:abc_murder), reading: "とうきょう")
    assert_equal "toukyou", word_sense.rhythm_pattern
  end

  test "reading を変更すると rhythm_pattern も追従する" do
    word_sense = word_senses(:curry)
    word_sense.update!(reading: "らーめん")
    assert_equal "raamen", word_sense.rhythm_pattern
  end

  test "生成カラム(reading_length/first_char/last_char)が DB で計算される" do
    word_sense = WordSense.create!(word: words(:abc_murder), reading: "さくら")
    word_sense.reload
    assert_equal 3, word_sense.reading_length
    assert_equal "さ", word_sense.first_char
    assert_equal "ら", word_sense.last_char
  end

  test "genre は小分類(level3)なら有効" do
    word_sense = WordSense.new(word: words(:abc_murder), reading: "さくら", genre: genres(:small_novel))
    assert word_sense.valid?
  end

  test "genre に大分類を指定すると無効" do
    word_sense = WordSense.new(word: words(:abc_murder), reading: "さくら", genre: genres(:large_literature))
    assert_not word_sense.valid?
    assert word_sense.errors.added?(:genre, :must_be_small)
  end

  test "genre に中分類を指定すると無効" do
    word_sense = WordSense.new(word: words(:abc_murder), reading: "さくら", genre: genres(:medium_japanese))
    assert_not word_sense.valid?
    assert word_sense.errors.added?(:genre, :must_be_small)
  end

  test "genre 未指定(nil)は有効" do
    assert WordSense.new(word: words(:abc_murder), reading: "さくら").valid?
  end

  test "entity_type / part_of_speech は任意" do
    word_sense = WordSense.new(word: words(:abc_murder), reading: "さくら",
                              entity_type: entity_types(:person_name), part_of_speech: parts_of_speech(:noun))
    assert word_sense.valid?
  end
end
