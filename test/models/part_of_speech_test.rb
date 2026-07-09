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

  # --- タグ統括管理 ---
  test "usage_count は付与している語義数を返す" do
    assert_equal 2, parts_of_speech(:noun).usage_count
    assert_equal 0, parts_of_speech(:verb).usage_count
  end

  test "未使用は削除でき、使用中は削除できない" do
    assert parts_of_speech(:verb).deletable?
    assert_not parts_of_speech(:noun).deletable?
  end

  test "merge_into! で語義の part_of_speech が付け替わる" do
    parts_of_speech(:noun).merge_into!(parts_of_speech(:verb))
    assert_not PartOfSpeech.exists?(parts_of_speech(:noun).id)
    assert_equal parts_of_speech(:verb), word_senses(:murder).reload.part_of_speech
    assert_equal parts_of_speech(:verb), word_senses(:curry).reload.part_of_speech
  end
end
