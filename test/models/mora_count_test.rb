require "test_helper"

class MoraCountTest < ActiveSupport::TestCase
  test "直音はそのまま拍数になる" do
    assert_equal 3, MoraCount.call("さくら")
  end

  test "拗音(きゃ/きょ)は1拍として数える" do
    assert_equal 1, MoraCount.call("きゃ")
    assert_equal 2, MoraCount.call("きょう")
    assert_equal 4, MoraCount.call("とうきょう")
  end

  test "促音 っ は独立した1拍" do
    assert_equal 4, MoraCount.call("がっこう")
  end

  test "撥音 ん は独立した1拍" do
    assert_equal 4, MoraCount.call("しんぶん")
  end

  test "長音符 ー は独立した1拍" do
    assert_equal 3, MoraCount.call("カレー")
    assert_equal 4, MoraCount.call("コーヒー")
  end

  test "外来音の小書き母音(ふぁ)は前の音に併合する" do
    assert_equal 1, MoraCount.call("ふぁ")
    assert_equal 4, MoraCount.call("ふぁいなる") # fa-i-na-ru
  end

  test "カタカナ・半角カナも同じ規則で数える" do
    assert_equal 4, MoraCount.call("ラーメン")
    assert_equal 4, MoraCount.call("ﾗｰﾒﾝ")
  end

  test "変換対象外の文字も1拍として数える" do
    assert_equal 3, MoraCount.call("あ・い")
  end

  test "空文字・nil は 0" do
    assert_equal 0, MoraCount.call("")
    assert_equal 0, MoraCount.call(nil)
  end
end
