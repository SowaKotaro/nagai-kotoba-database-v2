require "test_helper"

class MorphemeCloudTest < ActiveSupport::TestCase
  Entry = MorphemeFrequencies::Entry

  def entries_of(*specs)
    specs.map { |text, weight| Entry.new(text: text, count: 10, weight: weight) }
  end

  test "入力した語をすべて配置する(捨てない)" do
    entries = MorphemeFrequencies.entries
    layout = MorphemeCloud.place(entries)

    assert_equal entries.size, layout.items.size, "配置されなかった語がある"
    assert_equal entries.map(&:text).sort, layout.items.map(&:text).sort
  end

  test "語が増えても捨てずに高さを広げる" do
    few = MorphemeCloud.place(entries_of(*Array.new(10) { |i| [ "語#{i}", i / 9.0 ] }))
    many = MorphemeCloud.place(entries_of(*Array.new(80) { |i| [ "語#{i}", i / 79.0 ] }))

    assert_equal 10, few.items.size
    assert_equal 80, many.items.size
    assert many.height > few.height, "語が増えたのに高さが広がっていない"
  end

  test "配置が重ならない" do
    layout = MorphemeCloud.place(MorphemeFrequencies.entries)
    boxes = layout.items.map do |item|
      width = item.text.length * item.font_size
      # y はベースラインなので、字面は y から上へ伸びる
      [ item.x, item.y - item.font_size, item.x + width, item.y ]
    end

    boxes.combination(2).each do |a, b|
      overlap_x = a[0] < b[2] && b[0] < a[2]
      overlap_y = a[1] < b[3] && b[1] < a[3]
      assert_not(overlap_x && overlap_y, "重なっている: #{a.inspect} と #{b.inspect}")
    end
  end

  test "すべて枠の中に収まる" do
    layout = MorphemeCloud.place(MorphemeFrequencies.entries)

    layout.items.each do |item|
      assert_operator item.x, :>=, 0
      assert_operator item.x + (item.text.length * item.font_size), :<=, MorphemeCloud::VIEWBOX_WIDTH
      assert_operator item.y - item.font_size, :>=, 0
      assert_operator item.y, :<=, layout.height
    end
  end

  test "同じ入力からは必ず同じ配置になる" do
    entries = MorphemeFrequencies.entries
    first = MorphemeCloud.place(entries)
    second = MorphemeCloud.place(entries)

    assert_equal first.height, second.height
    assert_equal first.items.map { [ _1.text, _1.x, _1.y ] }, second.items.map { [ _1.text, _1.x, _1.y ] }
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
