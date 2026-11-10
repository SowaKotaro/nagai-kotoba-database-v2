require "test_helper"

class KeywordMatchTest < ActiveSupport::TestCase
  test "キーワードに当たる範囲を、照合順序 as_ci と同じ畳み方で求め、重なりをまとめて返す" do
    # ひらがなとカタカナ、小書きと並字を同じ字とみなす(ショ = しょ = シヨ)。清濁は区別する
    assert_equal [ 0...2, 3...5 ], KeywordMatch.ranges("しょうしよう", "ショ")
    assert_equal [], KeywordMatch.ranges("ハハ", "バ")

    # 全角と半角、欧字の大文字小文字を同じ字とみなす。接する範囲は 1 つにまとめる
    assert_equal [ 0...6 ], KeywordMatch.ranges("ＳＨＯsho", "sho")
    assert_equal [ 0...2 ], KeywordMatch.ranges("ｶﾀｶﾅ", "かた")

    # 重なって当たる箇所は 1 つの範囲にまとめる
    assert_equal [ 1...4 ], KeywordMatch.ranges("アーーー", "ーー")

    # 1 字ずつ畳むので、字の位置は変わらない。合成濁点(゙)は畳まずに残る(KANA_FOLD_SAMPLE の中身は test_helper)
    assert_equal [ 0...1, 4...5, 7...8 ], KeywordMatch.ranges(KANA_FOLD_SAMPLE, "カ")
    assert_equal [ 6...9 ], KeywordMatch.ranges(KANA_FOLD_SAMPLE, "ヴカケ")
    assert_equal [], KeywordMatch.ranges(KANA_FOLD_SAMPLE, "ガ")

    # キーワードの前後の空白は落とす。空なら何も当たらない
    assert_equal [ 0...3 ], KeywordMatch.ranges("カレーライス", " カレー ")
    assert_equal [], KeywordMatch.ranges("カレーライス", " ")
    assert_equal [], KeywordMatch.ranges(nil, "カレー")
  end
end
