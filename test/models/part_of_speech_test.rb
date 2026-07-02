require "test_helper"

class PartOfSpeechTest < ActiveSupport::TestCase
  test "テーブル名が parts_of_speech に解決される" do
    assert_equal "parts_of_speech", PartOfSpeech.table_name
  end

  test "name が空だと無効" do
    part_of_speech = PartOfSpeech.new(name: "")
    assert_not part_of_speech.valid?
    assert part_of_speech.errors.added?(:name, :blank)
  end

  test "name は一意" do
    dup = PartOfSpeech.new(name: parts_of_speech(:noun).name)
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: parts_of_speech(:noun).name)
  end

  test "name が異なれば有効" do
    assert PartOfSpeech.new(name: "形容詞").valid?
  end
end
