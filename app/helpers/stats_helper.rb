# 統計ページ(docs/stats.md)のチャート幾何計算。SVG はサーバ側(ERB)で描き、
# チャートライブラリは導入しない。ここでは座標・パスの計算だけを行い、
# 色・線種はビュー側の CSS クラス(components.css)に任せる。
module StatsHelper
  # 数字の壁の値の表示用整形(nil は「—」、小数の .0 は落とす、桁区切りあり)。
  def stats_number(value)
    return "—" if value.nil?

    value = value.to_i if value.is_a?(Float) && value == value.to_i
    number_with_delimiter(value)
  end

  # ==== §3 波形塗りバー ==============================================================

  WAVE_BAR_WIDTH = 40
  WAVE_BAR_GAP = 10
  WAVE_PLOT_HEIGHT = 260
  WAVE_TOP_PAD = 24      # 件数の直書き用
  WAVE_BOTTOM_PAD = 28   # 値ラベル用
  WAVE_SIDE_PAD = 8
  WAVE_AMPLITUDE = 2.6
  WAVE_CYCLES = 1

  # 分布 [{ value:, count: }] から波形塗りバーの描画データを組み立てる。
  # 直書きラベルは最頻値と両端のみ(全点に数字を振らない。docs/stats.md §1)。
  def stats_wave_bars(distribution)
    max_count = distribution.map { |bin| bin[:count] }.max.to_i
    mode_value = distribution.max_by { |bin| bin[:count] }&.fetch(:value)
    baseline = WAVE_TOP_PAD + WAVE_PLOT_HEIGHT

    bars = distribution.each_with_index.map do |bin, index|
      x = WAVE_SIDE_PAD + index * (WAVE_BAR_WIDTH + WAVE_BAR_GAP)
      height = max_count.positive? ? bin[:count] * (WAVE_PLOT_HEIGHT - WAVE_AMPLITUDE * 2) / max_count.to_f : 0
      height = 3 if bin[:count].positive? && height < 3
      {
        value: bin[:value], count: bin[:count],
        x: x, center_x: (x + WAVE_BAR_WIDTH / 2.0).round(1), top: (baseline - height).round(1),
        path: wave_bar_path(x, baseline - height, WAVE_BAR_WIDTH, baseline),
        mode: bin[:value] == mode_value,
        labeled: bin[:value] == mode_value || index.zero? || index == distribution.size - 1
      }
    end

    {
      width: WAVE_SIDE_PAD * 2 + distribution.size * (WAVE_BAR_WIDTH + WAVE_BAR_GAP) - WAVE_BAR_GAP,
      height: baseline + WAVE_BOTTOM_PAD,
      baseline: baseline,
      bars: bars
    }
  end

  # ==== §4 収録の推移(株価チャート式) ==============================================

  TIMELINE_WIDTH = 720
  TIMELINE_HEIGHT = 248
  TIMELINE_LEFT = 10
  TIMELINE_RIGHT = 14
  TIMELINE_PRICE_TOP = 14
  TIMELINE_PRICE_BOTTOM = 150
  TIMELINE_VOLUME_TOP = 168
  TIMELINE_VOLUME_BOTTOM = 224

  # 週次データ [{ start_on:, count:, cumulative: }] から累計の折れ線 + 出来高(週別新収録)の
  # 描画データを組み立てる。縦軸は表示期間内の累計の範囲に合わせる(株価チャートの文法)。
  def stats_timeline_chart(weeks)
    return nil if weeks.empty?

    xs = timeline_xs(weeks.size)
    lo, hi = timeline_price_range(weeks)
    points = weeks.each_with_index.map do |week, index|
      y = TIMELINE_PRICE_BOTTOM -
          (week[:cumulative] - lo) * (TIMELINE_PRICE_BOTTOM - TIMELINE_PRICE_TOP) / (hi - lo).to_f
      { x: xs[index], y: y.round(1), cumulative: week[:cumulative] }
    end

    line = points.map.with_index { |point, i| "#{i.zero? ? 'M' : 'L'}#{point[:x]},#{point[:y]}" }.join(" ")
    area = "#{line} L#{points.last[:x]},#{TIMELINE_PRICE_BOTTOM} L#{points.first[:x]},#{TIMELINE_PRICE_BOTTOM} Z"

    {
      width: TIMELINE_WIDTH, height: TIMELINE_HEIGHT,
      price_bottom: TIMELINE_PRICE_BOTTOM, volume_bottom: TIMELINE_VOLUME_BOTTOM,
      line: line, area: area, first: points.first, last: points.last,
      volume_bars: timeline_volume_bars(weeks, xs)
    }
  end

  # ==== ジャンルのサンバースト(Plotly 用データ) ====================================

  # 大→中→小の3階層を Plotly sunburst の並列配列(ids/labels/parents/values)へ展開する。
  # branchvalues: "total" 前提(親の値 = 子の合計)。genre_ids は各ノードのジャンル id で、
  # 末端(小分類)クリックでの絞り込み検索への遷移に使う(customdata)。
  def stats_genre_sunburst_data(genre_map)
    data = { ids: [], labels: [], parents: [], values: [], genre_ids: [] }
    genre_map[:groups].each do |large|
      push_sunburst_node(data, "L#{large[:id]}", large, "")
      large[:children].each do |medium|
        push_sunburst_node(data, "M#{medium[:id]}", medium, "L#{large[:id]}")
        medium[:children].each do |small|
          push_sunburst_node(data, "S#{small[:id]}", small, "M#{medium[:id]}")
        end
      end
    end
    data
  end

  # ==== エンティティ型のツリーマップ ================================================

  # レイアウト計算に使う仮想キャンバス(横:縦 = 2:1。CSS の aspect-ratio と一致させる)。
  TREEMAP_WIDTH = 200.0
  TREEMAP_HEIGHT = 100.0

  # [{ id:, name:, count: }](多い順) を、面積が件数に比例する矩形(squarified treemap)へ
  # 展開する。座標はコンテナに対する % (left/top/width/height)。
  def stats_entity_treemap(entities)
    total = entities.sum { |entity| entity[:count] }.to_f
    return [] if total.zero?

    items = entities.map { |entity| entity.merge(area: entity[:count] / total * TREEMAP_WIDTH * TREEMAP_HEIGHT) }
    rects = []
    squarify(items, 0.0, 0.0, TREEMAP_WIDTH, TREEMAP_HEIGHT, rects)
    rects.map do |rect|
      rect.except(:area, :x, :y, :w, :h).merge(
        left: (rect[:x] / TREEMAP_WIDTH * 100).round(3),
        top: (rect[:y] / TREEMAP_HEIGHT * 100).round(3),
        width: (rect[:w] / TREEMAP_WIDTH * 100).round(3),
        height: (rect[:h] / TREEMAP_HEIGHT * 100).round(3)
      )
    end
  end

  # ==== §7 母音スペクトル ============================================================

  SPECTRUM_WIDTH = 720
  SPECTRUM_HEIGHT = 240
  SPECTRUM_LEFT = 10
  SPECTRUM_RIGHT = 64   # 右端の段名の直書き用
  SPECTRUM_TOP = 12
  SPECTRUM_BOTTOM = 228
  # 段の並び(下から上)。ラベルはビューの i18n で「ア段」等に変える。
  SPECTRUM_VOWELS = SiteStatistics::VOWELS

  # 拍位置ごとの母音構成比 [{ position:, total:, counts: }] を積み上げ面グラフにする。
  # 各位置で構成比を 100% に正規化し、下から ア段→オ段 の順に積む。
  def stats_vowel_spectrum(positions)
    return nil if positions.size < 2

    xs = positions.each_index.map do |index|
      (SPECTRUM_LEFT + index * (SPECTRUM_WIDTH - SPECTRUM_LEFT - SPECTRUM_RIGHT) / (positions.size - 1).to_f).round(1)
    end
    # boundaries[k][i] = 位置 i における「下から k 段まで」の積み上げ上端の y 座標。
    boundaries = stacked_boundaries(positions)

    bands = SPECTRUM_VOWELS.each_with_index.map do |vowel, band|
      upper = boundaries[band + 1]
      lower = boundaries[band]
      forward = upper.each_with_index.map { |y, i| "#{i.zero? ? 'M' : 'L'}#{xs[i]},#{y}" }.join(" ")
      backward = (lower.size - 1).downto(0).map { |i| "L#{xs[i]},#{lower[i]}" }.join(" ")
      {
        vowel: vowel,
        path: "#{forward} #{backward} Z",
        label_y: ((upper.last + lower.last) / 2.0).round(1)
      }
    end
    spread_spectrum_labels(bands)

    { width: SPECTRUM_WIDTH, height: SPECTRUM_HEIGHT, xs: xs, bands: bands, label_x: SPECTRUM_WIDTH - SPECTRUM_RIGHT + 8 }
  end

  private

  # squarified treemap(Bruls らのアルゴリズム)。残り領域の短辺に沿って、
  # 矩形のアスペクト比が最も正方形に近づくところまで1列(row)に詰めては敷き詰める。
  def squarify(items, x, y, w, h, rects)
    return if items.empty?

    short_side = [ w, h ].min
    row = [ items.first ]
    rest = items.drop(1)
    while rest.any? && squarify_worst(row + [ rest.first ], short_side) <= squarify_worst(row, short_side)
      row << rest.shift
    end

    row_area = row.sum { |item| item[:area] }
    if w >= h
      # 縦に1列並べ、残りは右側の領域へ。
      row_width = row_area / h
      offset = y
      row.each do |item|
        rects << item.merge(x: x, y: offset, w: row_width, h: item[:area] / row_width)
        offset += item[:area] / row_width
      end
      squarify(rest, x + row_width, y, w - row_width, h, rects)
    else
      # 横に1行並べ、残りは下側の領域へ。
      row_height = row_area / w
      offset = x
      row.each do |item|
        rects << item.merge(x: offset, y: y, w: item[:area] / row_height, h: row_height)
        offset += item[:area] / row_height
      end
      squarify(rest, x, y + row_height, w, h - row_height, rects)
    end
  end

  # 列に含めた矩形の「最悪のアスペクト比」(正方形=1 に近いほど良い)。
  def squarify_worst(row, side)
    areas = row.map { |item| item[:area] }
    total = areas.sum
    [ (side**2) * areas.max / (total**2), (total**2) / ((side**2) * areas.min) ].max
  end

  def push_sunburst_node(data, node_id, node, parent_id)
    data[:ids] << node_id
    data[:labels] << node[:name]
    data[:parents] << parent_id
    data[:values] << node[:count]
    data[:genre_ids] << node[:id]
  end

  # 上辺を正弦波(振幅 2.6px・2周期)にした棒のパス。「読みの息の長さ」の見立て(docs/stats.md §3)。
  def wave_bar_path(x, top, width, bottom)
    steps = 24
    amplitude = [ WAVE_AMPLITUDE, (bottom - top) / 2.0 ].min
    crest = (0..steps).map do |step|
      px = x + width * step / steps.to_f
      py = top + amplitude * Math.sin(2 * Math::PI * WAVE_CYCLES * step / steps.to_f)
      "L#{px.round(2)},#{py.round(2)}"
    end
    "M#{x},#{bottom.round(1)} #{crest.join(' ')} L#{x + width},#{bottom.round(1)} Z"
  end

  def timeline_xs(size)
    span = TIMELINE_WIDTH - TIMELINE_LEFT - TIMELINE_RIGHT
    return [ TIMELINE_LEFT + span / 2.0 ] if size == 1

    size.times.map { |index| (TIMELINE_LEFT + index * span / (size - 1).to_f).round(1) }
  end

  # 縦軸の範囲(表示期間内の累計 min〜max に 8% の余白)。
  def timeline_price_range(weeks)
    cumulatives = weeks.map { |week| week[:cumulative] }
    lo = cumulatives.min
    hi = cumulatives.max
    pad = [ (hi - lo) * 0.08, 1 ].max
    [ lo - pad, hi + pad ]
  end

  def timeline_volume_bars(weeks, xs)
    max_count = weeks.map { |week| week[:count] }.max
    return [] unless max_count&.positive?

    step = xs.size > 1 ? xs[1] - xs[0] : TIMELINE_WIDTH / 2.0
    bar_width = [ [ step * 0.7, 8 ].min, 1.5 ].max.round(1)
    weeks.each_with_index.filter_map do |week, index|
      next if week[:count].zero?

      height = (week[:count] * (TIMELINE_VOLUME_BOTTOM - TIMELINE_VOLUME_TOP) / max_count.to_f).round(1)
      { x: (xs[index] - bar_width / 2).round(1), y: (TIMELINE_VOLUME_BOTTOM - height).round(1),
        width: bar_width, height: height, count: week[:count], last: index == weeks.size - 1 }
    end
  end

  # 右端の帯が薄いと段名ラベルが重なるため、上から順に最小間隔を確保する。
  # 押し下げてはみ出した分は全体を上へ戻す。
  def spread_spectrum_labels(bands, min_gap: 16)
    ordered = bands.sort_by { |band| band[:label_y] }
    ordered.each_cons(2) do |upper, lower|
      lower[:label_y] = [ lower[:label_y], upper[:label_y] + min_gap ].max
    end
    overflow = ordered.last[:label_y] - SPECTRUM_BOTTOM
    ordered.each { |band| band[:label_y] = (band[:label_y] - overflow).round(1) } if overflow.positive?
  end

  # 各拍位置の構成比を正規化し、段境界の y 座標(下から積み上げ)を段ごとに並べる。
  def stacked_boundaries(positions)
    plot_height = SPECTRUM_BOTTOM - SPECTRUM_TOP
    ratio_rows = positions.map do |position|
      total = [ position[:total], 1 ].max.to_f
      SPECTRUM_VOWELS.map { |vowel| position[:counts][vowel].to_i / total }
    end

    (0..SPECTRUM_VOWELS.size).map do |band|
      ratio_rows.map do |ratios|
        (SPECTRUM_BOTTOM - ratios.first(band).sum * plot_height).round(1)
      end
    end
  end
end
