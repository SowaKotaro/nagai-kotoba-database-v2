require "test_helper"

class WordTest < ActiveSupport::TestCase
  test "surface が空だと無効" do
    word = Word.new(surface: "")
    assert_not word.valid?
    assert word.errors.added?(:surface, :blank)
  end

  test "surface は一意" do
    dup = Word.new(surface: words(:abc_murder).surface)
    assert_not dup.valid?
    assert dup.errors.added?(:surface, :taken, value: words(:abc_murder).surface)
  end

  test "保存時に surface から char_type_pattern が自動生成される" do
    word = Word.create!(surface: "令和6年")
    assert_equal "漢漢@漢", word.char_type_pattern
  end

  test "surface を変更すると char_type_pattern も追従する" do
    word = Word.create!(surface: "カレー")
    assert_equal "アアア", word.char_type_pattern

    word.update!(surface: "ABC")
    assert_equal "AAA", word.char_type_pattern
  end

  test "char_type_pattern に手入力しても surface から上書きされる" do
    word = Word.create!(surface: "犬", char_type_pattern: "でたらめ")
    assert_equal "漢", word.char_type_pattern
  end
end
