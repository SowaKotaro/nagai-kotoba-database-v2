require "test_helper"

class StatsHelperTest < ActionView::TestCase
  include StatsHelper

  # ツリーマップは面積が件数に比例するので、件数の少ない型は名前も件数も読めない
  # マスになる。下限(0.5%)に満たない型は「その他」(id: nil)へ畳む。
  def entities(*counts)
    counts.each_with_index.map { |count, index| { id: index + 1, name: "型#{index + 1}", count: count } }
  end

  test "下限を超える型はそのまま並べ、その他は作らない" do
    rects = stats_entity_treemap(entities(50, 30, 20))
    assert_equal [ "型1", "型2", "型3" ], rects.map { |rect| rect[:name] }
    assert_empty rects.select { |rect| rect[:id].nil? }
  end

  test "下限に満たない型は末尾からその他へ畳む" do
    # 全 985 のうち下限は 4.9。2 を畳んでも届かないので 3 も巻き込む。
    rects = stats_entity_treemap(entities(900, 50, 30, 3, 2))
    other = rects.find { |rect| rect[:id].nil? }
    assert_equal I18n.t("stats.index.origins.entity_other"), other[:name]
    assert_equal 5, other[:count]
    assert_equal 2, other[:folded]
    assert_equal [ "型1", "型2", "型3" ], rects.reject { |rect| rect[:id].nil? }.map { |rect| rect[:name] }
  end

  test "畳む相手が1つだけなら面積が変わらないのでそのまま残す" do
    rects = stats_entity_treemap(entities(1000, 2))
    assert_equal [ "型1", "型2" ], rects.map { |rect| rect[:name] }
    assert_empty rects.select { |rect| rect[:id].nil? }
  end

  test "面が小さいマスほど級数を落とす" do
    rects = stats_entity_treemap(entities(900, 15, 6, 3, 2))
    scales = rects.to_h { |rect| [ rect[:name], rect[:scale] ] }

    assert_equal :normal, scales["型1"]
    assert_equal :small, scales["型2"]
    assert_equal :tiny, scales["型3"]
  end

  test "矩形はコンテナを埋め尽くし、面積は件数に比例する" do
    areas = stats_entity_treemap(entities(60, 40)).map { |rect| rect[:width] * rect[:height] / 100.0 }
    assert_in_delta 100.0, areas.sum, 0.01
    assert_in_delta 1.5, areas.first / areas.last, 0.01
  end

  # --- §7 母音の遷移グラフ ---

  # 層(拍位置) × 母音の件数から、そのまま描ける座標へ展開する。
  def transitions(layer_counts, edge_counts)
    layers = layer_counts.each_with_index.map do |counts, index|
      total = counts.values.sum
      nodes = SiteStatistics::VOWELS.map do |vowel|
        count = counts[vowel].to_i
        { vowel: vowel, count: count, share: total.zero? ? 0.0 : count / total.to_f }
      end
      { position: index + 1, total: total, nodes: nodes }
    end
    edges = edge_counts.map do |(position, from, to), count|
      total = edge_counts.sum { |(other, _, _), value| other == position ? value : 0 }
      { position: position, from: from, to: to, count: count, share: count / total.to_f }
    end
    { total: layers.first&.fetch(:total).to_i, layers: layers, edges: edges }
  end

  def two_layer_graph
    stats_vowel_graph(transitions(
      [ { "a" => 6, "i" => 2 }, { "a" => 4, "o" => 4 } ],
      { [ 1, "a", "a" ] => 6, [ 1, "i", "o" ] => 2 }
    ))
  end

  test "層が1つしか無ければ遷移が描けないので nil を返す" do
    assert_nil stats_vowel_graph(transitions([ { "a" => 3 } ], {}))
    assert_nil stats_vowel_graph({ total: 0, layers: [], edges: [] })
  end

  test "ノードは層ごとに5つ、件数によらず同じ大きさで置く" do
    graph = two_layer_graph
    first = graph[:layers].first[:nodes]

    assert_equal 5, first.size
    # 多寡はエッジだけで見せる(オーナー指示 2026-09-10)
    assert_equal [ StatsHelper::GRAPH_RADIUS ], graph[:layers].flat_map { |layer| layer[:nodes] }.map { |node| node[:r] }.uniq
    # 同じ層のノードは同じ x、母音ごとに y が決まる
    assert_equal 1, first.map { |node| node[:cx] }.uniq.size
    assert_equal first.map { |node| node[:cy] }, graph[:rows].map { |row| row[:y] }
  end

  test "キャンバスの幅は層の数ぶんだけ伸びる" do
    narrow = stats_vowel_graph(transitions([ { "a" => 2 }, { "a" => 2 } ], { [ 1, "a", "a" ] => 2 }))
    wide = stats_vowel_graph(transitions([ { "a" => 2 }, { "a" => 2 }, { "a" => 2 } ],
                                         { [ 1, "a", "a" ] => 2, [ 2, "a", "a" ] => 2 }))

    assert_equal narrow[:width] + StatsHelper::GRAPH_COLUMN_PITCH, wide[:width]
    assert_equal narrow[:height], wide[:height]
  end

  test "エッジは0件の組を落とし、最多の1本だけを強調する" do
    graph = two_layer_graph

    assert_equal 2, graph[:edges].size
    top = graph[:edges].select { |edge| edge[:top] }
    assert_equal 1, top.size
    assert_equal %w[a a], [ top.first[:from], top.first[:to] ]
    assert_operator top.first[:stroke], :>, graph[:edges].reject { |edge| edge[:top] }.first[:stroke]
  end

  test "ノードもエッジもキャンバスからはみ出さない" do
    graph = two_layer_graph

    graph[:layers].flat_map { |layer| layer[:nodes] }.each do |node|
      assert_operator node[:cx] - node[:r], :>=, 0
      assert_operator node[:cx] + node[:r], :<=, graph[:width]
      assert_operator node[:cy] - node[:r], :>=, 0
      assert_operator node[:cy] + node[:r], :<=, graph[:height]
    end
  end

  test "対象が無ければ空を返す" do
    assert_empty stats_entity_treemap([])
    assert_empty stats_entity_treemap(entities(0))
  end
end
