require "test_helper"

class EntityTypeTest < ActiveSupport::TestCase
  test "name が空だと無効" do
    entity_type = EntityType.new(name: "")
    assert_not entity_type.valid?
    assert entity_type.errors.added?(:name, :blank)
  end

  test "name は一意" do
    dup = EntityType.new(name: entity_types(:person_name).name)
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: entity_types(:person_name).name)
  end

  test "name が異なれば有効" do
    assert EntityType.new(name: "地名").valid?
  end

  # --- タグ統括管理(usage_count / deletable? / merge_into!) ---
  test "usage_count は付与している語義数を返す" do
    assert_equal 1, entity_types(:book_title).usage_count
    assert_equal 0, entity_types(:person_name).usage_count
  end

  test "未使用は削除でき、使用中は削除できない" do
    assert entity_types(:person_name).deletable?
    assert_not entity_types(:book_title).deletable?
  end

  test "参照中のエンティティタイプは destroy できない" do
    et = entity_types(:book_title)
    assert_not et.destroy
    assert EntityType.exists?(et.id)
  end

  test "merge_into! で語義の entity_type が付け替わり統合元が消える" do
    source = entity_types(:book_title)
    target = entity_types(:person_name)
    source.merge_into!(target)
    assert_not EntityType.exists?(source.id)
    assert_equal target, word_senses(:murder).reload.entity_type
  end

  test "merge_into! は同一タグ・別クラスを拒否する" do
    et = entity_types(:person_name)
    assert_raises(ArgumentError) { et.merge_into!(et) }
    assert_raises(ArgumentError) { et.merge_into!(parts_of_speech(:noun)) }
  end
end
