require "test_helper"

class WordSenseVariantTest < ActiveSupport::TestCase
  test "surface と word_sense は必須で、同じ語義に同じ表記は二重登録できない(reading は任意)" do
    variant = WordSenseVariant.new(surface: "")
    assert_not variant.valid?
    assert variant.errors.added?(:surface, :blank)
    assert variant.errors.added?(:word_sense, :blank)

    # 同じ語義に同じ表記は二重登録できない
    variant = WordSenseVariant.new(word_sense: word_senses(:curry), surface: word_sense_variants(:curry_variant).surface)
    assert_not variant.valid?
    assert variant.errors.added?(:surface, :taken, value: word_sense_variants(:curry_variant).surface)

    # reading は任意(無くても有効)
    assert WordSenseVariant.new(word_sense: word_senses(:murder), surface: "殺人事件").valid?
  end
end
