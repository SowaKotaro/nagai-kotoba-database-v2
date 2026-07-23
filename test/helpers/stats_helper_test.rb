require "test_helper"

class StatsHelperTest < ActionView::TestCase
  include StatsHelper

  # ツリーマップは面積が件数に比例するので、件数の少ない型は名前も件数も読めない
  # マスになる。下限(3%)に満たない型は「その他」(id: nil)へ畳む。
  def entities(*counts)
    counts.each_with_index.map { |count, index| { id: index + 1, name: "型#{index + 1}", count: count } }
  end

  test "下限を超える型はそのまま並べ、その他は作らない" do
    rects = stats_entity_treemap(entities(50, 30, 20))
    assert_equal [ "型1", "型2", "型3" ], rects.map { |rect| rect[:name] }
    assert_empty rects.select { |rect| rect[:id].nil? }
  end

  test "下限に満たない型は末尾からその他へ畳む" do
    rects = stats_entity_treemap(entities(90, 5, 3, 1, 1))
    other = rects.find { |rect| rect[:id].nil? }
    assert_equal I18n.t("stats.index.origins.entity_other"), other[:name]
    # 3語義の型も、畳んだ側が下限(3%)に届くまで巻き込む。
    assert_equal 5, other[:count]
    assert_equal 3, other[:folded]
    assert_equal [ "型1", "型2" ], rects.reject { |rect| rect[:id].nil? }.map { |rect| rect[:name] }
  end

  test "畳む相手が1つだけなら面積が変わらないのでそのまま残す" do
    rects = stats_entity_treemap(entities(98, 2))
    assert_equal [ "型1", "型2" ], rects.map { |rect| rect[:name] }
    assert_empty rects.select { |rect| rect[:id].nil? }
  end

  test "矩形はコンテナを埋め尽くし、面積は件数に比例する" do
    areas = stats_entity_treemap(entities(60, 40)).map { |rect| rect[:width] * rect[:height] / 100.0 }
    assert_in_delta 100.0, areas.sum, 0.01
    assert_in_delta 1.5, areas.first / areas.last, 0.01
  end

  test "対象が無ければ空を返す" do
    assert_empty stats_entity_treemap([])
    assert_empty stats_entity_treemap(entities(0))
  end
end
