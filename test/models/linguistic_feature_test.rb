require "test_helper"

class LinguisticFeatureTest < ActiveSupport::TestCase
  test "name が空だと無効" do
    linguistic_feature = LinguisticFeature.new(name: "")
    assert_not linguistic_feature.valid?
    assert linguistic_feature.errors.added?(:name, :blank)
  end

  test "name は一意" do
    dup = LinguisticFeature.new(name: linguistic_features(:rendaku).name)
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: linguistic_features(:rendaku).name)
  end

  test "name が異なれば有効" do
    assert LinguisticFeature.new(name: "湯桶読み").valid?
  end
end
