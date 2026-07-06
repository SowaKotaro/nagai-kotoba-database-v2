require "test_helper"

class CharTypePatternTest < ActiveSupport::TestCase
  test "各文字種が正しい記号に写像される" do
    assert_equal "漢", CharTypePattern.call("殺")
    assert_equal "あ", CharTypePattern.call("き")
    assert_equal "ア", CharTypePattern.call("カ")
    assert_equal "A", CharTypePattern.call("A")
    assert_equal "@", CharTypePattern.call("!")
  end

  test "混在した表層形を1文字ずつ変換する" do
    assert_equal "AAA漢漢漢漢", CharTypePattern.call("ABC殺人事件")
  end

  test "拗音・促音のひらがなも あ 扱い" do
    assert_equal "あああ", CharTypePattern.call("きゃっ")
  end

  test "長音符はカタカナ(ア)として扱う" do
    assert_equal "アアアアアア", CharTypePattern.call("カレーライス")
    assert_equal "アアアア", CharTypePattern.call("ラーメン")
  end

  test "半角カタカナ・半角長音符もカタカナ(ア)" do
    assert_equal "アアアア", CharTypePattern.call("ｺｰﾋｰ")
  end

  test "全角・半角の英字はどちらも A" do
    assert_equal "AAAAAA", CharTypePattern.call("AbＡｂzＺ")
  end

  test "数字は半角・全角ともに その他(@)" do
    assert_equal "@@@@", CharTypePattern.call("12３４")
  end

  test "記号・空白・絵文字は その他(@)" do
    assert_equal "@@@@", CharTypePattern.call("!? 😀")
  end

  test "繰り返し記号 々 は漢字扱い、〆 は その他" do
    assert_equal "漢漢", CharTypePattern.call("人々")
    assert_equal "@", CharTypePattern.call("〆")
  end

  test "漢字と数字の混在(年は漢字)" do
    assert_equal "漢漢@漢", CharTypePattern.call("令和6年")
  end

  test "nil と空文字は空文字列を返す" do
    assert_equal "", CharTypePattern.call(nil)
    assert_equal "", CharTypePattern.call("")
  end
end
