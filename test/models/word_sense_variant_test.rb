require "test_helper"

class WordSenseVariantTest < ActiveSupport::TestCase
  test "surface が空だと無効" do
    variant = WordSenseVariant.new(word_sense: word_senses(:curry), surface: "")
    assert_not variant.valid?
    assert variant.errors.added?(:surface, :blank)
  end

  test "word_sense が無いと無効" do
    variant = WordSenseVariant.new(surface: "カリー")
    assert_not variant.valid?
    assert variant.errors.added?(:word_sense, :blank)
  end

  test "同じ語義に同じ表記は二重登録できない" do
    variant = WordSenseVariant.new(word_sense: word_senses(:curry), surface: word_sense_variants(:curry_variant).surface)
    assert_not variant.valid?
    assert variant.errors.added?(:surface, :taken, value: word_sense_variants(:curry_variant).surface)
  end

  test "reading は任意(無くても有効)" do
    assert WordSenseVariant.new(word_sense: word_senses(:murder), surface: "殺人事件").valid?
  end

  test "語義から別表記を辿れる" do
    assert_includes word_senses(:curry).word_sense_variants, word_sense_variants(:curry_variant)
  end
end
