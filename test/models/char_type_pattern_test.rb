require "test_helper"

class CharTypePatternTest < ActiveSupport::TestCase
  test "文字種の記号へ1文字ずつ写像する" do
    assert_equal "漢", CharTypePattern.call("殺")
    assert_equal "あ", CharTypePattern.call("き")
    assert_equal "ア", CharTypePattern.call("カ")
    assert_equal "1", CharTypePattern.call("7")
    assert_equal "A", CharTypePattern.call("A")
    assert_equal "a", CharTypePattern.call("z")
    assert_equal "@", CharTypePattern.call("!")

    # 混在した表層形を1文字ずつ変換する
    assert_equal "AAA漢漢漢漢", CharTypePattern.call("ABC殺人事件")

    # 拗音・促音のひらがなも あ 扱い
    assert_equal "あああ", CharTypePattern.call("きゃっ")

    # 長音符はカタカナ(ア)として扱う
    assert_equal "アアアアアア", CharTypePattern.call("カレーライス")
    assert_equal "アアアア", CharTypePattern.call("ラーメン")

    # 半角カタカナ・半角長音符もカタカナ(ア)
    assert_equal "アアアア", CharTypePattern.call("ｺｰﾋｰ")

    # 記号・空白・絵文字は その他(@)
    assert_equal "@@@@", CharTypePattern.call("!? 😀")

    # 繰り返し記号 々 は漢字扱い、〆 は その他
    assert_equal "漢漢", CharTypePattern.call("人々")
    assert_equal "@", CharTypePattern.call("〆")

    # 漢字と数字の混在(年は漢字)
    assert_equal "漢漢1漢", CharTypePattern.call("令和6年")

    # nil と空文字は空文字列を返す
    assert_equal "", CharTypePattern.call(nil)
    assert_equal "", CharTypePattern.call("")
  end

  test "英数字は大小を区別して全角半角は畳む" do
    # A(半角大) b(半角小) Ａ(全角大) ｂ(全角小) z(半角小) Ｚ(全角大)
    assert_equal "AaAaaA", CharTypePattern.call("AbＡｂzＺ")

    # 数字は半角・全角ともに 1
    assert_equal "1111", CharTypePattern.call("12３４")

    # 英数字混在で大小・数字を写し取る(全角半角は畳む)
    # Ｗ(全角大) ｅ(全角小) ｂ(全角小) ３(全角数字) .(記号) ０(全角数字)
    assert_equal "Aaa1@1", CharTypePattern.call("Ｗｅｂ３.０")
  end
end
