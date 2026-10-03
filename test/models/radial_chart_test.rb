require "test_helper"

class RadialChartTest < ActiveSupport::TestCase
  # ジャンル一覧の横棒は、ビューのラムダ(20 + d * 80.0 / span を丸める)から RadialChart.percent に移した。
  # 比率を 100 倍してから丸めると 1 ずれる値があるので、移す前の演算順のままであることを総当たりで確かめる。
  test "percent は移す前のビューの式と、最小値からの差・幅のすべての組で一致する" do
    mismatches = (1..400).flat_map do |span|
      (0..span).filter_map do |delta|
        expected = (20 + delta * 80.0 / span).round
        [ delta, span ] unless RadialChart.percent(100 + delta, 100, 100 + span) == expected
      end
    end
    assert_empty mismatches
  end

  test "percent は最小値と最大値が同じなら 100 を返す" do
    assert_equal 100, RadialChart.percent(7, 7, 7)
  end
end
