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
end
