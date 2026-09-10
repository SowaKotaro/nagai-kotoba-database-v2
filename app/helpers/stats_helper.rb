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
        value: bin[:value], count: bin[:count], overflow: bin[:overflow] || false,
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

  # レイアウト計算に使う仮想キャンバス(横:縦 = 3:2。CSS の aspect-ratio と一致させる)。
  # 2:1 から縦を伸ばしたのは、出す型を 8 → 38 に増やした 2026-09-10 に、
  # 1マスあたりの面積を確保するため(同じ幅なら 3:2 の方が 1.3 倍広い)。
  TREEMAP_WIDTH = 300.0
  TREEMAP_HEIGHT = 200.0
  # 「その他」へ畳む下限(全体に占める割合)。これを下回る型は末尾から畳む。
  # 3% にしていた頃は 55 型が畳まれて「その他」が全体の 45% を占め、
  # いちばん大きい面が「その他」という本末転倒な図になっていた(2026-09-10 オーナー指摘)。
  # 0.5% まで下げると 38 型が出て「その他」は 4% に収まる。
  # 級数は面の大きさに合わせて 3 段(TREEMAP_SMALL_SHARE / TREEMAP_TINY_SHARE)に落とす。
  TREEMAP_MIN_SHARE = 0.005
  # 面が小さいマスの級数を落とす境目(全体に占める割合)。
  TREEMAP_SMALL_SHARE = 0.02
  TREEMAP_TINY_SHARE = 0.008

  # [{ id:, name:, count: }](多い順) を、面積が件数に比例する矩形(squarified treemap)へ
  # 展開する。座標はコンテナに対する % (left/top/width/height)。
  # 細かすぎる型は「その他」(id: nil)にまとめてから割り付ける。
  def stats_entity_treemap(entities)
    total = entities.sum { |entity| entity[:count] }.to_f
    return [] if total.zero?

    items = fold_small_entities(entities, total)
             .map { |entity| entity.merge(area: entity[:count] / total * TREEMAP_WIDTH * TREEMAP_HEIGHT) }
    rects = []
    squarify(items, 0.0, 0.0, TREEMAP_WIDTH, TREEMAP_HEIGHT, rects)
    rects.map do |rect|
      rect.except(:area, :x, :y, :w, :h).merge(
        left: (rect[:x] / TREEMAP_WIDTH * 100).round(3),
        top: (rect[:y] / TREEMAP_HEIGHT * 100).round(3),
        width: (rect[:w] / TREEMAP_WIDTH * 100).round(3),
        height: (rect[:h] / TREEMAP_HEIGHT * 100).round(3),
        scale: treemap_scale(rect[:count] / total)
      )
    end
  end

  # ==== §7 母音の遷移グラフ ==========================================================

  # 層(拍位置)を横に並べ、各層に母音5つのノードを縦に置いて、隣り合う層を全結合で結ぶ。
  # 座標はスペクトルと同じく仮想キャンバスで持ち、viewBox 付き SVG で拡縮する。
  #
  # キャンバスの幅は層の数から決める(15層で 818px)。画面に収まらないぶんは
  # 親(.stats-scroll)を横へスクロールさせ、図そのものは縮めない。
  # 間隔は「本文カラム(約 816px)に 10 拍ぶんが収まる」ところから決めている
  # (段名の 52 + 14 + 80×9 + 14 = 800。オーナー指示 2026-09-10)。11拍目からはスクロールの先。
  GRAPH_COLUMN_PITCH = 80  # 層と層の間隔
  GRAPH_ROW_PITCH = 46     # 母音5段の間隔
  GRAPH_LEFT = 14          # 図の左の余白(段名は横スクロールしない別の SVG に出す)
  GRAPH_RIGHT = 14
  # 段名(ア段〜オ段)を置く、横スクロールしない左の列の幅。
  GRAPH_LABEL_WIDTH = 52
  GRAPH_TOP = 16
  GRAPH_BOTTOM = 26        # 下端の拍位置の逃げ
  GRAPH_HEIGHT = GRAPH_TOP + (GRAPH_ROW_PITCH * 4) + GRAPH_BOTTOM
  # ノードは件数によらず同じ大きさ(オーナー指示 2026-09-10)。多寡はエッジだけで見せる。
  GRAPH_RADIUS = 6.5
  # 「多い遷移だけ」に絞るときの下限。偏りが無ければどの組も 1/25 = 4% になるので、
  # その 1.5 倍(6%)を「その位置で目立って多い」とみなす。
  GRAPH_UNIFORM_SHARE = 1.0 / (5 * 5)
  GRAPH_SIGNIFICANT_RATIO = 1.5
  # エッジの太さと濃さ。350 本を重ねるので、細く薄く始めて上限も抑える。
  GRAPH_MIN_EDGE = 0.3
  GRAPH_MAX_EDGE = 3.2
  GRAPH_MIN_OPACITY = 0.1
  GRAPH_MAX_OPACITY = 0.55

  # SiteStatistics#vowel_transitions を、そのまま描ける座標へ展開する。
  # 層が2つ未満(遷移が1本も無い)なら nil を返し、ビューは区画ごと出さない。
  def stats_vowel_graph(transitions)
    layers = transitions[:layers]
    return nil if layers.size < 2

    xs = graph_columns(layers.size)
    ys = graph_rows
    # 注記で名指しする「最も多い遷移」。**割合ではなく件数**で採る。
    # 後ろの区間ほど標本が減るので、割合で採ると 30 語義しか通らない線が
    # 1,468 語義の線を抜いて「最多」になってしまう。同率なら位置の早い方。
    # (図の上では塗り分けない。色を持つのは押して選んだ線だけ)
    top_edge = transitions[:edges].max_by { |edge| edge[:count] }

    {
      width: xs.last + GRAPH_RIGHT,
      height: GRAPH_HEIGHT,
      label_width: GRAPH_LABEL_WIDTH,
      label_x: GRAPH_LABEL_WIDTH - 10,
      axis_y: GRAPH_HEIGHT - 8,
      rows: SiteStatistics::VOWELS.map { |vowel| { vowel: vowel, y: ys[vowel] } },
      layers: graph_nodes(layers, xs, ys),
      edges: graph_edges(transitions[:edges], xs, ys, top_edge)
    }
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

  # 層の x 座標(等間隔)。幅は層の数ぶんだけ伸びる。
  def graph_columns(count)
    (0...count).map { |index| GRAPH_LEFT + (GRAPH_COLUMN_PITCH * index) }
  end

  # 母音ごとの y 座標(上から ア→オ の5段)。
  def graph_rows
    SiteStatistics::VOWELS.each_with_index.to_h do |vowel, index|
      [ vowel, GRAPH_TOP + (GRAPH_ROW_PITCH * index) ]
    end
  end

  def graph_nodes(layers, xs, ys)
    layers.each_with_index.map do |layer, index|
      nodes = layer[:nodes].map do |node|
        node.merge(cx: xs[index], cy: ys[node[:vowel]], r: GRAPH_RADIUS)
      end
      layer.merge(nodes: nodes)
    end
  end

  # 太さと濃さは「その区間の遷移に占める割合」の、全区間を通した最大値で正規化する。
  def graph_edges(edges, xs, ys, top_edge)
    max_share = edges.filter_map { |edge| edge[:share] }.max.to_f

    edges.filter_map do |edge|
      next if edge[:count].zero?

      ratio = max_share.zero? ? 0.0 : edge[:share] / max_share
      edge.merge(
        x1: xs[edge[:position] - 1], y1: ys[edge[:from]],
        x2: xs[edge[:position]], y2: ys[edge[:to]],
        stroke: (GRAPH_MIN_EDGE + ((GRAPH_MAX_EDGE - GRAPH_MIN_EDGE) * ratio)).round(2),
        opacity: (GRAPH_MIN_OPACITY + ((GRAPH_MAX_OPACITY - GRAPH_MIN_OPACITY) * ratio)).round(3),
        significant: edge[:share] >= (GRAPH_UNIFORM_SHARE * GRAPH_SIGNIFICANT_RATIO),
        top: edge.equal?(top_edge)
      )
    end
  end

  # 面の大きさに応じた級数の段。小さいマスに 14px の名前を置くと、はみ出して
  # 名前も件数も読めなくなる(小さいマスほど名前を短く置きたい)。
  def treemap_scale(share)
    if share < TREEMAP_TINY_SHARE then :tiny
    elsif share < TREEMAP_SMALL_SHARE then :small
    else :normal
    end
  end

  # 面積が下限(TREEMAP_MIN_SHARE)に満たない型を、件数の少ない方から「その他」へ畳む。
  # 畳んだ「その他」自体が下限に届かないうちは、次に小さい型も巻き込む。
  # 畳む相手が1つしか無いときは面積が変わらず名前が消えるだけなので、そのまま残す。
  def fold_small_entities(entities, total)
    floor = total * TREEMAP_MIN_SHARE
    major = entities.sort_by { |entity| -entity[:count] }
    minor = []
    minor_count = 0
    while major.size > 1 && (major.last[:count] < floor || (minor.any? && minor_count < floor))
      minor_count += major.last[:count]
      minor << major.pop
    end
    return entities if minor.size < 2

    major + [ { id: nil, name: t("stats.index.origins.entity_other"), count: minor_count, folded: minor.size } ]
  end

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
