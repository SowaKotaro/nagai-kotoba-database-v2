require "test_helper"

class KanaFoldTest < ActiveSupport::TestCase
  # KANA_FOLD_SAMPLE: 半角カナ「ｶﾞｷﾞ」・合成濁点つきの「か」・ゔ・ゕ・ゖ(test_helper)。
  test "to_katakana は NFKC で半角カナ・合成濁点を畳み、ゔ・ゕ・ゖ もカタカナへ寄せる" do
    assert_equal "ガギガヴヵヶ", KanaFold.to_katakana(KANA_FOLD_SAMPLE)
  end

  test "to_katakana(nfkc: false) は半角カナ・合成濁点を書かれたまま残し、ひらがなだけを寄せる" do
    expected = [ 0xFF76, 0xFF9E, 0xFF77, 0xFF9E, 0x30AB, 0x3099, 0x30F4, 0x30F5, 0x30F6 ].pack("U*")
    assert_equal expected, KanaFold.to_katakana(KANA_FOLD_SAMPLE, nfkc: false)
  end

  test "to_hiragana は NFKC で畳んでからカタカナをひらがなへ寄せる" do
    assert_equal "がぎがゔゕゖ", KanaFold.to_hiragana(KANA_FOLD_SAMPLE)
    assert_equal "しゃーろっと", KanaFold.to_hiragana("ｼｬｰﾛｯﾄ")
  end

  # 照合順序 as_ci と同じく、かなの種類は畳むが清濁は畳まない。
  test "清濁は区別し、かな以外は変えない" do
    assert_equal [ "バ", "ハ", "パ" ], %w[ば は ぱ].map { |kana| KanaFold.to_katakana(kana) }
    assert_equal "ABC殺人", KanaFold.to_katakana("ABC殺人")
    assert_equal "", KanaFold.to_katakana(nil)
  end
end
