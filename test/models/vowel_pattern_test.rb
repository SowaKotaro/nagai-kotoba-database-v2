require "test_helper"

class VowelPatternTest < ActiveSupport::TestCase
  test "ローマ字から母音のみを抜き出す" do
    assert_equal "ouou", VowelPattern.call("toukyou")
    assert_equal "auiie", VowelPattern.call("satsujinjiken")
  end

  test "長音展開済みの母音も残る" do
    assert_equal "aee", VowelPattern.call("karee")
  end

  test "撥音 n や子音(y を含む)は落ちる" do
    assert_equal "iu", VowelPattern.call("shinbun")
    assert_equal "ou", VowelPattern.call("kyou")
  end

  test "空文字・nil は空文字列" do
    assert_equal "", VowelPattern.call("")
    assert_equal "", VowelPattern.call(nil)
  end
end
