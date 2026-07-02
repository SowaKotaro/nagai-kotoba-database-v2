require "test_helper"

class WordSenseFeatureTest < ActiveSupport::TestCase
  # 有効な属性一式(word_sense murder = ABC殺人事件 / さつじんじけん の一部)。
  def valid_attributes(**overrides)
    { word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku),
      target: "事件", target_reading: "じけん" }.merge(overrides)
  end

  test "一式が揃っていれば有効" do
    assert WordSenseFeature.new(valid_attributes).valid?
  end

  test "word_sense が無いと無効" do
    wsf = WordSenseFeature.new(valid_attributes(word_sense: nil))
    assert_not wsf.valid?
    assert wsf.errors.added?(:word_sense, :blank)
  end

  test "linguistic_feature が無いと無効" do
    wsf = WordSenseFeature.new(valid_attributes(linguistic_feature: nil))
    assert_not wsf.valid?
    assert wsf.errors.added?(:linguistic_feature, :blank)
  end

  test "target が空だと無効" do
    wsf = WordSenseFeature.new(valid_attributes(target: ""))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target, :blank)
  end

  test "target_reading が空だと無効" do
    wsf = WordSenseFeature.new(valid_attributes(target_reading: ""))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target_reading, :blank)
  end

  test "target が表層形に含まれないと無効" do
    wsf = WordSenseFeature.new(valid_attributes(target: "犬"))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target, :not_in_surface)
  end

  test "target_reading が読みに含まれないと無効" do
    wsf = WordSenseFeature.new(valid_attributes(target_reading: "いぬ"))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target_reading, :not_in_reading)
  end

  test "同じ語義×特徴×該当部分の重複は無効" do
    dup = WordSenseFeature.new(valid_attributes(target: "殺人", target_reading: "さつじん"))
    assert_not dup.valid?
    assert dup.errors.of_kind?(:target, :taken)
  end

  test "同じ語義×特徴でも該当部分が違えば有効" do
    # murder には既に 連濁:殺人 がある。別の該当部分 事件 なら追加できる。
    assert WordSenseFeature.new(valid_attributes(target: "事件", target_reading: "じけん")).valid?
  end

  test "別の語義になら同じ特徴・同じ該当部分でも有効" do
    wsf = WordSenseFeature.new(word_sense: word_senses(:curry), linguistic_feature: linguistic_features(:rendaku),
                              target: "カレー", target_reading: "カレー")
    assert wsf.valid?
  end
end
