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

  test "word_senses を多対多で辿れる" do
    assert_includes linguistic_features(:rendaku).word_senses, word_senses(:murder)
  end

  test "語義から参照されている特徴は削除できない" do
    feature = linguistic_features(:rendaku)
    assert_not feature.destroy
    assert LinguisticFeature.exists?(feature.id)
    assert feature.errors.of_kind?(:base, :"restrict_dependent_destroy.has_many")
  end

  test "参照されていない特徴は削除できる" do
    feature = LinguisticFeature.create!(name: "湯桶読み")
    assert feature.destroy
  end
end
