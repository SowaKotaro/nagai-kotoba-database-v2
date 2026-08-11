# 級数見本(統計 §1)の配置を決める値オブジェクト(Issue 78)。
#
# 大きい語をばらばらに置き、空いた隙間へ小さい語を詰めていく(オーナー指示 2026-08-11)。
# 頻度順に流す文字組ではなく、隙間が埋まっていく密度そのものを見どころにする。
#
# 座標は VIEWBOX_WIDTH × VIEWBOX_HEIGHT の仮想平面で計算し、描画側は viewBox 付きの
# インライン SVG に流す(KanaRing と同じ作法)。SVG なら幅に応じて素直に拡縮するので、
# 絶対配置でもモバイルで崩れず、字の大小の比も保たれる。
#
# 配置は乱数を使うが**種を固定**するので、同じ入力からは必ず同じ絵になる。
# 描画のたびに動くとキャッシュも効かず、画面を見比べることもできないため。
class MorphemeCloud
  VIEWBOX_WIDTH = 680

  # 高さは語の総面積から決める(定数にしない)。
  # 固定にすると、収録が増えて語が大きくなったときに入りきらず、黙って捨てることになる。
  # 実際、固定 400 では 60 件中 24 件が落ちていた。
  #
  # TARGET_FILL は「字の外接矩形が埋める割合」の目安。上げるほど詰まるが、
  # 詰めきれず総当たりに落ちる語が増えて計算が重くなる。
  # 実データ(60件)で測ると 0.70 が頃合い(字面占有 51%・5ms)。
  # 0.76 以上は密度がほとんど変わらないのに 140ms 超へ跳ね上がる。
  TARGET_FILL = 0.70
  MIN_VIEWBOX_HEIGHT = 240
  # 入りきらなかったときに高さを広げる倍率と、その試行回数。
  GROWTH = 1.12
  MAX_GROWTH_STEPS = 6

  # 級数の下限・上限。下限は、モバイル幅(実寸で約 350px = 約半分に縮む)でも
  # 読める大きさから逆算している。上限との比が大きすぎても小さすぎても見本にならない。
  MIN_FONT_SIZE = 20.0
  MAX_FONT_SIZE = 88.0

  # 当たり判定の升目。細かいほど密に詰まるが計算量が増える。
  CELL = 4
  COLUMNS = (VIEWBOX_WIDTH / CELL.to_f).ceil

  # 語どうしが触れないよう、当たり判定に足す余白(升目数)。
  PADDING_CELLS = 1

  # 1語あたりに試す候補位置の数。全升目を試すと重いので、混ぜた候補から先着で決める。
  MAX_ATTEMPTS = 900

  # 配置が毎回同じになるよう種を固定する。
  SEED = 20260811

  # 配置済みの1語。x/y は文字の左下(SVG の text の基準点)。
  Placed = Data.define(:text, :count, :weight, :font_size, :x, :y, :top) do
    def top? = top
  end

  # 配置の結果。描画側は height を viewBox に使う。
  Layout = Data.define(:items, :height) do
    def any? = items.any?
  end

  def self.place(entries) = new(entries).place

  def initialize(entries)
    @entries = Array(entries)
  end

  # 全語が入るまで高さを広げながら詰める。1語も捨てないことを優先する
  # (捨てると集計の一部が黙って消え、note の件数とも食い違うため)。
  def place
    boxes = build_boxes
    return Layout.new(items: [], height: MIN_VIEWBOX_HEIGHT) if boxes.empty?

    height = initial_height(boxes)
    MAX_GROWTH_STEPS.times do
      items = pack(boxes, height)
      return Layout.new(items: items, height: height) if items.size == boxes.size

      height = (height * GROWTH).ceil
    end

    # ここまで来ることは実データでは無いが、最後の結果をそのまま返す(落ちる語が出る)。
    Layout.new(items: pack(boxes, height), height: height)
  end

  private

  # 語ごとの級数と、当たり判定に使う升目の大きさを先に出す。
  def build_boxes
    @entries.sort_by { |entry| -entry.weight }.map do |entry|
      font_size = font_size_for(entry)
      {
        entry: entry,
        font_size: font_size,
        width_cells: cells(text_width(entry.text, font_size)) + (PADDING_CELLS * 2),
        height_cells: cells(font_size * 1.08) + (PADDING_CELLS * 2)
      }
    end
  end

  # 外接矩形の総面積を目安の充填率で割って、必要な高さを見積もる。
  def initial_height(boxes)
    area = boxes.sum { |box| box[:width_cells] * box[:height_cells] } * CELL * CELL
    [ (area / (VIEWBOX_WIDTH * TARGET_FILL)).ceil, MIN_VIEWBOX_HEIGHT ].max
  end

  # 大きい順に置いていく(先に置いた大きい語の隙間へ、あとの小さい語が入り込む)。
  def pack(boxes, height)
    total_rows = (height / CELL.to_f).ceil
    rows = Array.new(total_rows, 0) # 各行の占有状況をビットで持つ
    random = Random.new(SEED)

    boxes.filter_map do |box|
      next if box[:width_cells] > COLUMNS || box[:height_cells] > total_rows

      spot = find_spot(rows, box[:width_cells], box[:height_cells], random, total_rows)
      next unless spot

      occupy(rows, spot, box[:width_cells], box[:height_cells])
      build_placed(box, spot)
    end
  end

  # 級数は頻度の位置(0.0〜1.0)をそのまま大きさに写す。
  def font_size_for(entry)
    (MIN_FONT_SIZE + (entry.weight * (MAX_FONT_SIZE - MIN_FONT_SIZE))).round(1)
  end

  # 日本語の全角文字はほぼ正方形なので、字数 × 級数で幅を見積もれる。
  # 半角(英数字)は約半分として数える。
  def text_width(text, font_size)
    units = text.each_char.sum { |char| char.match?(/[ -~｡-ﾟ]/) ? 0.5 : 1.0 }
    units * font_size
  end

  def cells(length) = (length / CELL.to_f).ceil

  # まず無作為に当たり(大きい語をばらけさせるため)、見つからなければ総当たりで探す。
  #
  # 無作為だけだと、後半の小さい語は盤面がほぼ埋まっているせいで当たりを引けず、
  # 空きがあるのに捨てられてしまう(実データで 60 件中 23 件が落ちていた)。
  # 隙間を埋めるのがこの図の見どころなので、最後は必ず総当たりで拾う。
  def find_spot(rows, width_cells, height_cells, random, total_rows)
    max_column = COLUMNS - width_cells
    max_row = total_rows - height_cells
    return nil if max_column.negative? || max_row.negative?

    mask = (1 << width_cells) - 1

    MAX_ATTEMPTS.times do
      column = random.rand(max_column + 1)
      row = random.rand(max_row + 1)
      return [ column, row ] if free?(rows, column, row, mask, height_cells)
    end

    scan_spot(rows, max_column, max_row, mask, height_cells)
  end

  # 左上から順に走査して最初の空きを返す。当たり判定は行ごとのビット演算なので安い。
  def scan_spot(rows, max_column, max_row, mask, height_cells)
    (0..max_row).each do |row|
      (0..max_column).each do |column|
        return [ column, row ] if free?(rows, column, row, mask, height_cells)
      end
    end
    nil
  end

  def free?(rows, column, row, mask, height_cells)
    height_cells.times do |offset|
      return false if rows[row + offset].anybits?(mask << column)
    end
    true
  end

  def occupy(rows, spot, width_cells, height_cells)
    column, row = spot
    mask = ((1 << width_cells) - 1) << column
    height_cells.times { |offset| rows[row + offset] |= mask }
  end

  def build_placed(box, spot)
    column, row = spot
    entry = box[:entry]
    Placed.new(
      text: entry.text, count: entry.count, weight: entry.weight, font_size: box[:font_size],
      x: ((column + PADDING_CELLS) * CELL).round(1),
      # SVG の text は下端(ベースライン)基準なので、確保した高さの下側へ寄せる。
      y: (((row + box[:height_cells] - PADDING_CELLS) * CELL) - (box[:font_size] * 0.2)).round(1),
      top: entry.top?
    )
  end
end
