require "test_helper"

class MorphemeCloudTest < ActiveSupport::TestCase
  Entry = MorphemeFrequencies::Entry

  # 実データ(db/morpheme_frequencies.json)を詰めるのは1回で 1 秒近くかかる。配置を読むだけのテストは
  # 1回だけ詰めた結果を使い回す。並列実行ではワーカーごとに詰め直さないよう、フォーク前の読み込み時に詰める。
  REAL_LAYOUT = MorphemeCloud.place(MorphemeFrequencies.entries)

  def real_layout = REAL_LAYOUT

  def entries_of(*specs)
    specs.map { |text, weight| Entry.new(text: text, count: 10, weight: weight) }
  end

  test "入力した語をすべて、重ならず枠の中に配置する" do
    layout = real_layout
    assert_equal MorphemeFrequencies.entries.map(&:text).sort, layout.items.map(&:text).sort, "配置されなかった語がある"

    # 字面の矩形は (x, top_y) から width × height(欧文は全角より狭いので、
    # 字数からではなく配置に使った見積もりで見る)
    boxes = layout.items.map do |item|
      assert_operator item.x, :>=, 0
      assert_operator item.x + item.width, :<=, MorphemeCloud::VIEWBOX_WIDTH
      assert_operator item.top_y, :>=, 0
      assert_operator item.top_y + item.height, :<=, layout.height
      [ item.x, item.top_y, item.x + item.width, item.top_y + item.height ]
    end

    boxes.combination(2).each do |a, b|
      overlap_x = a[0] < b[2] && b[0] < a[2]
      overlap_y = a[1] < b[3] && b[1] < a[3]
      assert_not(overlap_x && overlap_y, "重なっている: #{a.inspect} と #{b.inspect}")
    end
  end

  test "語が増えても捨てずに高さを広げる" do
    few = MorphemeCloud.place(entries_of(*Array.new(10) { |i| [ "語#{i}", i / 9.0 ] }))
    many = MorphemeCloud.place(entries_of(*Array.new(80) { |i| [ "語#{i}", i / 79.0 ] }))

    assert_equal 10, few.items.size
    assert_equal 80, many.items.size
    assert many.height > few.height, "語が増えたのに高さが広がっていない"
  end

  test "字面が紙の7割以上を埋める(余白が見えないくらい詰める)" do
    layout = real_layout
    ink = layout.items.sum { |item| item.width * item.height }
    ratio = ink / (MorphemeCloud::VIEWBOX_WIDTH * layout.height).to_f

    assert_operator ratio, :>=, 0.70, "字面占有が #{(ratio * 100).round(1)}% しかない"
  end

  test "最頻の1語だけは中心に据える" do
    layout = real_layout
    top = layout.items.find(&:top?)

    # 升目に丸めるぶんのずれは許す(升目 数個ぶん)
    assert_in_delta MorphemeCloud::VIEWBOX_WIDTH / 2.0, top.x + (top.width / 2), MorphemeCloud::CELL * 3
    assert_in_delta layout.height / 2.0, top.top_y + (top.height / 2), MorphemeCloud::CELL * 3
  end

  test "色は語そのものから決まり、8色とも使われる" do
    palettes = real_layout.items.to_h { |item| [ item.text, item.palette ] }

    assert(palettes.values.all? { |palette| (1..MorphemeCloud::PALETTE_SIZE).cover?(palette) })
    # 8色とも使われる(データが 100 件あるのに色が偏っていないか)
    assert_equal MorphemeCloud::PALETTE_SIZE, palettes.values.uniq.size
    # String#hash のようにプロセスごとに変わる値を使っていないので、既知の語の色は固定できる
    assert_equal 4, MorphemeCloud.place(entries_of([ "方程式", 1.0 ])).items.first.palette
  end

  test "同じ入力からは必ず同じ配置・同じ色になる" do
    snapshot = ->(layout) { [ layout.height, layout.items.map { |item| [ item.text, item.x, item.y, item.palette ] } ] }

    assert_equal snapshot.call(real_layout), snapshot.call(MorphemeCloud.place(MorphemeFrequencies.entries))
  end

  test "layout は同じ入力なら詰め直さず、入力が変われば作り直す" do
    entries = MorphemeFrequencies.entries
    first = MorphemeCloud.layout(entries)

    assert_same first, MorphemeCloud.layout(entries.dup), "同じ入力なのに詰め直している"
    assert_not_same first, MorphemeCloud.layout(entries.first(5)), "入力が変わったのに作り直していない"
  end

  test "頻度が高いほど大きい活字になる" do
    layout = MorphemeCloud.place(entries_of([ "小", 0.0 ], [ "中", 0.5 ], [ "大", 1.0 ]))
    sizes = layout.items.to_h { [ _1.text, _1.font_size ] }

    assert_operator sizes["大"], :>, sizes["中"]
    assert_operator sizes["中"], :>, sizes["小"]
    assert_in_delta MorphemeCloud::MIN_FONT_SIZE, sizes["小"], 0.1
    assert_in_delta MorphemeCloud::MAX_FONT_SIZE, sizes["大"], 0.1
  end

  test "空の入力でも落ちない" do
    layout = MorphemeCloud.place([])
    assert_empty layout.items
    assert_operator layout.height, :>, 0
  end
end
