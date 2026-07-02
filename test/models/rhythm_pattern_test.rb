require "test_helper"

class RhythmPatternTest < ActiveSupport::TestCase
  test "基本的な直音を変換する" do
    assert_equal "sakura", RhythmPattern.call("さくら")
  end

  test "ヘボン式の子音(shi/chi/tsu/fu/ji)" do
    assert_equal "shi", RhythmPattern.call("し")
    assert_equal "chi", RhythmPattern.call("ち")
    assert_equal "tsu", RhythmPattern.call("つ")
    assert_equal "fu", RhythmPattern.call("ふ")
    assert_equal "ji", RhythmPattern.call("じ")
  end

  test "拗音(しゃ→sha, きょ→kyo)" do
    assert_equal "sha", RhythmPattern.call("しゃ")
    assert_equal "kyou", RhythmPattern.call("きょう")
  end

  test "促音は次の子音を重ねる" do
    assert_equal "gakkou", RhythmPattern.call("がっこう")
  end

  test "促音+ちは t を置く(ヘボン式)" do
    assert_equal "matcha", RhythmPattern.call("まっちゃ")
    assert_equal "kotchi", RhythmPattern.call("こっち")
  end

  test "撥音は常に n(b/p/m の前でも m にしない)" do
    assert_equal "shinbun", RhythmPattern.call("しんぶん")
    assert_equal "sanpo", RhythmPattern.call("さんぽ")
  end

  test "長音は母音をそのまま展開する" do
    assert_equal "toukyou", RhythmPattern.call("とうきょう")
  end

  test "長音符 ー は直前の母音を繰り返す" do
    assert_equal "karee", RhythmPattern.call("カレー")
    assert_equal "koohii", RhythmPattern.call("コーヒー")
  end

  test "カタカナ・半角カナも同じ規則で変換する" do
    assert_equal "raamen", RhythmPattern.call("ラーメン")
    assert_equal "raamen", RhythmPattern.call("ﾗｰﾒﾝ")
  end

  test "ぢ/づ は ji/zu、を は o" do
    assert_equal "tsuzuki", RhythmPattern.call("つづき")
    assert_equal "hanaji", RhythmPattern.call("はなぢ")
    assert_equal "o", RhythmPattern.call("を")
  end

  test "変換表に無い文字はそのまま通す" do
    assert_equal "a・i", RhythmPattern.call("あ・い")
  end

  test "空文字・nil は空文字列" do
    assert_equal "", RhythmPattern.call("")
    assert_equal "", RhythmPattern.call(nil)
  end
end
