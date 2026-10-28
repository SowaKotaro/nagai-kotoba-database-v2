require "test_helper"

class RhythmPatternTest < ActiveSupport::TestCase
  test "ヘボン式で直音・拗音・促音・撥音を変換する" do
    assert_equal "sakura", RhythmPattern.call("さくら")

    # ヘボン式の子音(shi/chi/tsu/fu/ji)
    assert_equal "shi", RhythmPattern.call("し")
    assert_equal "chi", RhythmPattern.call("ち")
    assert_equal "tsu", RhythmPattern.call("つ")
    assert_equal "fu", RhythmPattern.call("ふ")
    assert_equal "ji", RhythmPattern.call("じ")

    # 拗音(しゃ→sha, きょ→kyo)
    assert_equal "sha", RhythmPattern.call("しゃ")
    assert_equal "kyou", RhythmPattern.call("きょう")

    # 促音は次の子音を重ねる
    assert_equal "gakkou", RhythmPattern.call("がっこう")

    # 促音+ちは t を置く(ヘボン式)
    assert_equal "matcha", RhythmPattern.call("まっちゃ")
    assert_equal "kotchi", RhythmPattern.call("こっち")

    # 撥音は常に n(b/p/m の前でも m にしない)
    assert_equal "shinbun", RhythmPattern.call("しんぶん")
    assert_equal "sanpo", RhythmPattern.call("さんぽ")

    # ぢ/づ は ji/zu、を は o
    assert_equal "tsuzuki", RhythmPattern.call("つづき")
    assert_equal "hanaji", RhythmPattern.call("はなぢ")
    assert_equal "o", RhythmPattern.call("を")
  end

  test "長音・かなの種類・表に無い文字・空の扱い" do
    assert_equal "toukyou", RhythmPattern.call("とうきょう")

    # 長音符 ー は直前の母音を繰り返す
    assert_equal "karee", RhythmPattern.call("カレー")
    assert_equal "koohii", RhythmPattern.call("コーヒー")

    # カタカナ・半角カナも同じ規則で変換する
    assert_equal "raamen", RhythmPattern.call("ラーメン")
    assert_equal "raamen", RhythmPattern.call("ﾗｰﾒﾝ")

    # 変換表に無い文字はそのまま通す
    assert_equal "a・i", RhythmPattern.call("あ・い")

    # 空文字・nil は空文字列
    assert_equal "", RhythmPattern.call("")
    assert_equal "", RhythmPattern.call(nil)

    # 半角カナ・合成濁点・ゔ は畳んでローマ字にし、ゕ・ゖ は残る
    # かなの畳み込み(T0-18): NFKC で畳んでからローマ字にする。ゕ・ゖ はローマ字にならずそのまま残る。
    assert_equal "gagigavu" + [ 0x3095, 0x3096 ].pack("U*"), RhythmPattern.call(KANA_FOLD_SAMPLE)
  end
end
