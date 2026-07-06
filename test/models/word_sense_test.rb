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

  test "保存時に reading から vowel_pattern / mora_count が自動生成される" do
    word_sense = WordSense.create!(word: words(:abc_murder), reading: "とうきょう")
    assert_equal "ouou", word_sense.vowel_pattern
    assert_equal 4, word_sense.mora_count
  end

  test "reading を変更すると vowel_pattern / mora_count も追従する" do
    word_sense = word_senses(:curry)
    word_sense.update!(reading: "らーめん")
    assert_equal "aae", word_sense.vowel_pattern
    assert_equal 4, word_sense.mora_count
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

  test "linguistic_features を多対多で辿れる" do
    assert_includes word_senses(:murder).linguistic_features, linguistic_features(:rendaku)
    assert_includes word_senses(:murder).linguistic_features, linguistic_features(:jubako)
  end

  test "語義を削除すると中間レコードも削除される" do
    word_sense = word_senses(:murder)
    feature_ids = word_sense.word_sense_features.ids
    assert_not_empty feature_ids

    word_sense.destroy
    assert_empty WordSenseFeature.where(id: feature_ids)
    # マスタ(linguistic_features)自体は削除されない。
    assert LinguisticFeature.exists?(linguistic_features(:rendaku).id)
  end

  test "同じ特徴でも該当部分が違えば追加できる" do
    word_sense = word_senses(:murder) # 既に 連濁:殺人 がある
    word_sense.word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku),
                                           target: "事件", target_reading: "じけん")
    assert_equal 2, word_sense.word_sense_features.where(linguistic_feature: linguistic_features(:rendaku)).count
  end

  test "同じ特徴・同じ該当部分の重複は保存に失敗する" do
    word_sense = word_senses(:murder) # 既に 連濁:殺人 がある
    assert_raises(ActiveRecord::RecordInvalid) do
      word_sense.word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku),
                                             target: "殺人", target_reading: "さつじん")
    end
  end

  test "語義の更新で親 word の updated_at が進む(touch。Issue 26)" do
    word = words(:abc_murder)
    word.update_column(:updated_at, 1.day.ago)
    before = word.reload.updated_at

    word.word_senses.first.update!(meaning: "更新後の意味")

    assert_operator word.reload.updated_at, :>, before
  end
end
