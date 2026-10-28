require "test_helper"

class VowelPatternTest < ActiveSupport::TestCase
  test "ローマ字から母音だけを抜き出す(撥音 n・子音は落ち、空は空)" do
    assert_equal "ouou", VowelPattern.call("toukyou")
    assert_equal "auiie", VowelPattern.call("satsujinjiken")

    # 長音展開済みの母音も残る
    assert_equal "aee", VowelPattern.call("karee")

    # 撥音 n や子音(y を含む)は落ちる
    assert_equal "iu", VowelPattern.call("shinbun")
    assert_equal "ou", VowelPattern.call("kyou")

    # 空文字・nil は空文字列
    assert_equal "", VowelPattern.call("")
    assert_equal "", VowelPattern.call(nil)
  end
end
