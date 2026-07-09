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

  # --- タグ統括管理 ---
  test "usage_count は付与している語義数を返す" do
    assert_equal 1, linguistic_features(:rendaku).usage_count
    assert_equal 0, LinguisticFeature.create!(name: "湯桶読み").usage_count
  end

  test "merge_into! は中間表を付け替える" do
    linguistic_features(:jubako).merge_into!(linguistic_features(:rendaku))
    assert_not LinguisticFeature.exists?(linguistic_features(:jubako).id)
    # murder の「事件」特徴が rendaku に付け替わっている(元の殺人=rendaku とは該当部分が違うので両立)
    assert WordSenseFeature.exists?(
      word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku), target: "事件"
    )
  end

  test "merge_into! は該当部分が衝突すると重複を作らない" do
    # murder に rendaku(事件/5) を足すと jubako(事件/5) と統合先で衝突する。
    WordSenseFeature.create!(
      word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku),
      target: "事件", target_reading: "じけん", target_start: 5
    )
    linguistic_features(:jubako).merge_into!(linguistic_features(:rendaku))
    assert_not LinguisticFeature.exists?(linguistic_features(:jubako).id)
    count = WordSenseFeature.where(
      word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku),
      target: "事件", target_start: 5
    ).count
    assert_equal 1, count
  end
end
