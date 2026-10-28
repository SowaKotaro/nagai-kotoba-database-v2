require "test_helper"

class MoraCountTest < ActiveSupport::TestCase
  test "拗音と外来音の小書き母音は前と併せて1拍、促音・撥音・長音符は独立した1拍" do
    assert_equal 3, MoraCount.call("さくら")

    # 拗音(きゃ/きょ)は1拍として数える
    assert_equal 1, MoraCount.call("きゃ")
    assert_equal 2, MoraCount.call("きょう")
    assert_equal 4, MoraCount.call("とうきょう")

    # 促音 っ は独立した1拍
    assert_equal 4, MoraCount.call("がっこう")

    # 撥音 ん は独立した1拍
    assert_equal 4, MoraCount.call("しんぶん")

    # 長音符 ー は独立した1拍
    assert_equal 3, MoraCount.call("カレー")
    assert_equal 4, MoraCount.call("コーヒー")

    # 外来音の小書き母音(ふぁ)は前の音に併合する
    assert_equal 1, MoraCount.call("ふぁ")
    assert_equal 4, MoraCount.call("ふぁいなる") # fa-i-na-ru
  end

  test "かなの種類・対象外の文字・空の扱い" do
    assert_equal 4, MoraCount.call("ラーメン")
    assert_equal 4, MoraCount.call("ﾗｰﾒﾝ")

    # 変換対象外の文字も1拍として数える
    assert_equal 3, MoraCount.call("あ・い")

    # 空文字・nil は 0
    assert_equal 0, MoraCount.call("")
    assert_equal 0, MoraCount.call(nil)

    # 半角カナ・合成濁点・ゔ・ゕ・ゖ を含む読みのモーラ数
    # かなの畳み込み(T0-18): ガ・ギ・ガ・ヴ・ゕ・ゖ の 6 拍として数える。
    assert_equal 6, MoraCount.call(KANA_FOLD_SAMPLE)
  end
end
