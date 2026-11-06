require "test_helper"

# 共有カードの背景の「長い言葉の壁」の配置。既定カード(script/og_default.py)も同じ設定を読む。
# 語そのもの(有名な言葉を選ぶ方針)は config/share_card_wall.json の note と docs/design.md §5.1。
class ShareCardWallTest < ActiveSupport::TestCase
  test "どの行も左端の外から右端まで語で埋まり、語どうしは重ならず、同じ語は 1 度しか出ない" do
    wall = ShareCardWall.default
    items = wall.items
    rows = items.group_by(&:y)
    config = JSON.parse(ShareCardWall::CONFIG_PATH.read)

    assert_equal 9, rows.size
    rows.each_value do |row|
      assert_operator row.first.x, :<=, 0
      assert_operator row.last.x, :<, WordShareCard::WIDTH
      row.each_cons(2) do |left, right|
        width = ShareCardTypesetter.new(left.text, width: 1, tracking: 0, bold: true).width_em * wall.font_size
        assert_operator right.x, :>=, left.x + width, "#{left.text} と #{right.text} が重なる"
      end
    end
    # 同じ語を繰り返さない(words が足りないと先頭へ戻って繰り返す。語を減らしたときに気づけるように)
    assert_equal items.size, items.map(&:text).uniq.size
    assert_equal config.fetch("words"), items.map(&:text)
    # 行は語を順に流した続きから始まり、行頭の x は indents で行ごとに決まる。上の 3 行の先頭を固定しておく。
    # 2 行目は、先頭の「ウィトルウィウス的人体図」の「ウ」が半分見切れる位置(オーナー指示)
    assert_equal config.fetch("rows"), config.fetch("indents").size
    assert_equal [ [ -40.0, "東京証券取引所" ], [ -22.0, "ウィトルウィウス的人体図" ], [ -386.0, "グレートバリアリーフ" ] ],
                 rows.values.first(3).map { |row| [ row.first.x, row.first.text ] }
    # 上の行の中央と下の行の中央に出る語(オーナーが残すと決めた 2 語)
    assert_equal "将を射んと欲すれば先ず馬を射よ", rows.values.first.find { |item| item.x.between?(250, 400) }.text
    assert_equal "ブリュメール18日のクーデター", rows.values.last.find { |item| item.x.between?(300, 450) }.text
    assert_equal items, ShareCardWall.new(config).items
  end
end
