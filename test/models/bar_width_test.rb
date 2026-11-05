require "test_helper"

class BarWidthTest < ActiveSupport::TestCase
  # ジャンル一覧の横棒は、ビューのラムダ(20 + d * 80.0 / span を丸める)から移した。
  # 比率を 100 倍してから丸めると 1 ずれる値があるので、移す前の演算順のままであることを総当たりで確かめる。
  test "最小値〜最大値を 20〜100% に写し、移す前のビューの式と一致する(最小値と最大値が同じなら 100)" do
    mismatches = (1..400).flat_map do |span|
      (0..span).filter_map do |delta|
        expected = (20 + delta * 80.0 / span).round
        [ delta, span ] unless BarWidth.call(100 + delta, 100, 100 + span) == expected
      end
    end
    assert_empty mismatches

    assert_equal 100, BarWidth.call(7, 7, 7)
  end
end
