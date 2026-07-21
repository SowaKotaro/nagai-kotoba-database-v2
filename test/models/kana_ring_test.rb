require "test_helper"

class KanaRingTest < ActiveSupport::TestCase
  test "nodes は基本46字(ンを含む)を五十音順で持つ" do
    chars = KanaRing.nodes.map(&:char)
    assert_equal 46, chars.size
    assert_equal KanaRow::BASE_46, chars, "五十音順(ア〜ン)で並ぶ"
  end

  test "全字が単一の外周円上(中心から等距離)に並ぶ" do
    KanaRing.nodes.each do |node|
      distance = Math.hypot(node.cx - KanaRing::CENTER, node.cy - KanaRing::CENTER)
      assert_in_delta KanaRing::RADIUS, distance, 0.05, "#{node.char} が円周上にない"
    end
  end

  test "ア は頂点(真上)・ン はその手前(左上)に置かれる" do
    nodes = KanaRing.nodes.index_by(&:char)
    assert_in_delta KanaRing::CENTER, nodes["ア"].cx, 0.01
    assert_operator nodes["ア"].cy, :<, KanaRing::CENTER, "アは中心より上"
    # ンは五十音順の末尾 → 頂点アのすぐ左手前(cx < 中心, cy < 中心)
    assert_operator nodes["ン"].cx, :<, KanaRing::CENTER
    assert_operator nodes["ン"].cy, :<, KanaRing::CENTER
  end

  test "path は読みを基本字へ畳んで読み順に並べる" do
    chars = KanaRing.path("ガッコウ").map(&:char)
    assert_equal %w[カ ツ コ ウ], chars
  end

  test "path は長音符など基本46字に載らない文字を除く" do
    chars = KanaRing.path("コーヒー").map(&:char)
    assert_equal %w[コ ヒ], chars
  end

  test "path はひらがなもカタカナへ寄せて畳む" do
    chars = KanaRing.path("にほんご").map(&:char)
    assert_equal %w[ニ ホ ン コ], chars
  end

  test "visited_chars は経路が通った字の集合を返す" do
    assert_equal Set["コ", "ツ"], KanaRing.visited_chars("こっこ")
  end

  test "空・かな以外だけの読みは経路が空になる" do
    assert_empty KanaRing.path("")
    assert_empty KanaRing.path("ーー")
  end

  test "交差の無い読みは交差数0" do
    # ア→カ→サ→タ は五十音順に単調に進むので弦は入れ子(交差しない)
    assert_equal 0, KanaRing.crossing_count("アカサタ")
    assert_equal 0, KanaRing.crossing_count("ア")
  end

  test "弦が交互に並ぶ読みは交差数を数える" do
    # ア(0)→サ(10)→カ(5)→タ(15): 弦(0-10)と(5-15)が交互に並び1交差
    assert_equal 1, KanaRing.crossing_count("アサカタ")
  end

  test "端点を共有するエッジ(隣接・再訪)や退化は交差に数えない" do
    # 往復は弦を共有するだけで交差しない
    assert_equal 0, KanaRing.crossing_count("アサア")
    # 同じ字の連続(退化したエッジ)も交差しない
    assert_equal 0, KanaRing.crossing_count("アアサ")
  end
end
