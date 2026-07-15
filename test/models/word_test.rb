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
    assert_equal "漢漢1漢", word.char_type_pattern
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

  test "surface に混入した改行は保存時に除去される(内部の空白は残す)" do
    word = Word.create!(surface: "Dead by\r\nDaylight\n")
    assert_equal "Dead by Daylight", word.surface
  end

  test "annotated / unannotated scope は annotated_at の有無で分かれる" do
    assert_includes Word.annotated, words(:abc_murder)
    assert_not_includes Word.annotated, words(:pending_haruhi)
    assert_includes Word.unannotated, words(:pending_haruhi)
    assert_not_includes Word.unannotated, words(:abc_murder)
    # 保留も annotated_at なしなので unannotated(未公開)に含まれる
    assert_includes Word.unannotated, words(:on_hold_word)
  end

  test "annotation_status は未対応/保留/完了の3状態" do
    assert words(:pending_haruhi).annotation_pending?
    assert words(:on_hold_word).annotation_on_hold?
    assert words(:abc_murder).annotation_done?

    assert_includes Word.annotation_pending, words(:pending_haruhi)
    assert_includes Word.annotation_on_hold, words(:on_hold_word)
    assert_includes Word.annotation_done, words(:abc_murder)
    # コンソールのキュー(未対応)には保留・完了は出ない
    assert_not_includes Word.annotation_pending, words(:on_hold_word)
    assert_not_includes Word.annotation_pending, words(:abc_murder)
  end

  test "mark_annotated は annotated_at と状態(完了)を立てる" do
    word = words(:pending_haruhi)
    word.mark_annotated
    assert_not_nil word.annotated_at
    assert word.annotation_done?
  end

  test "mark_on_hold は状態を保留にし annotated_at を落とす" do
    word = words(:pending_haruhi)
    word.mark_on_hold
    assert word.annotation_on_hold?
    assert_nil word.annotated_at
  end
end
