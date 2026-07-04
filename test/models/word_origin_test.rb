require "test_helper"

class WordOriginTest < ActiveSupport::TestCase
  test "name が空だと無効" do
    word_origin = WordOrigin.new(name: "")
    assert_not word_origin.valid?
    assert word_origin.errors.added?(:name, :blank)
  end

  test "name は一意" do
    dup = WordOrigin.new(name: word_origins(:wago).name)
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: word_origins(:wago).name)
  end

  test "name が異なれば有効" do
    assert WordOrigin.new(name: "タミル語").valid?
  end

  test "word_senses を多対多で辿れる" do
    assert_includes word_origins(:kango).word_senses, word_senses(:murder)
  end

  test "語義から参照されている語種は削除できない" do
    origin = word_origins(:kango)
    assert_not origin.destroy
    assert WordOrigin.exists?(origin.id)
    assert origin.errors.of_kind?(:base, :"restrict_dependent_destroy.has_many")
  end

  test "参照されていない語種は削除できる" do
    origin = WordOrigin.create!(name: "タミル語")
    assert origin.destroy
  end
end
