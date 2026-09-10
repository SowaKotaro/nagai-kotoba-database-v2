# ワードクラウド(統計 §1)の配置を決める値オブジェクト(Issue 78)。
#
# 最頻の1語を中心に据え、残りはばらばらに置いて隙間を詰めていく
# (オーナー指示 2026-08-11 / 中心据えと「余白が見えないくらい」は 2026-09-10)。
# 頻度順に流す文字組ではなく、隙間が埋まっていく密度そのものを見どころにする。
#
# 詰まり具合(字の外接矩形が紙を埋める割合)は実データ 100 件で **77%**。
# 効いているのは次の4つで、いずれも「余白を削る」ではなく「無駄な確保をやめる」もの。
#   1. 語ごとに字面の高さを変える(欧文だけの語に和文と同じ高さを取らせない)
#   2. 置き場所は無作為に選んだ行の空きから、**いちばん既存の語に接する位置**を採る
#   3. 入る高さが見つかったら、入らなくなる手前まで二分探索で詰め直す
#   4. 欧文の幅は字ごとの表で見積もる(平均で見積もると隣へ食い込む)
#
# 座標は VIEWBOX_WIDTH × 算出した高さの仮想平面で計算し、描画側は viewBox 付きの
# インライン SVG に流す(KanaRing と同じ作法)。SVG なら幅に応じて素直に拡縮するので、
# 絶対配置でもモバイルで崩れず、字の大小の比も保たれる。
#
# 配置は乱数を使うが**種を固定**するので、同じ入力からは必ず同じ絵になる。
# 描画のたびに動くとキャッシュも効かず、画面を見比べることもできないため。
class MorphemeCloud
  require "zlib"

  VIEWBOX_WIDTH = 680

  # 高さは語の総面積から決める(定数にしない)。
  # 固定にすると、収録が増えて語が大きくなったときに入りきらず、黙って捨てることになる。
  # 実際、固定 400 では 60 件中 24 件が落ちていた。
  #
  # TARGET_FILL は「字の外接矩形が埋める割合」の目安。ここは**探索の出発点**でしかなく、
  # 入ったあとに二分探索で詰め直すので、多少ずれていても最終的な高さは変わらない。
  TARGET_FILL = 0.88
  MIN_VIEWBOX_HEIGHT = 240
  # 二分探索をここまで詰めたら打ち切る(px)。
  HEIGHT_EPSILON = 8
  # 入りきらなかったときに高さを広げる倍率と、その試行回数。
  # 刻みが粗いと必要以上に広がって図が薄くなるので、細かく刻んで回数で補う
  # (詰め直しは総当たりがビット演算になった 2026-09-10 以降は1回 30〜80ms と安い)。
  GROWTH = 1.06
  MAX_GROWTH_STEPS = 12
  # 入る高さが見つかったあと、下限との間を二分探索する回数。
  SEARCH_STEPS = 6

  # 級数の下限・上限。図の高さはこの2つでほぼ決まる。
  # 100 件が 680 × 507 におさまる値(スマホ幅では下限が実寸 8px 前後まで縮む)。
  MIN_FONT_SIZE = 18.0
  MAX_FONT_SIZE = 64.0

  # 当たり判定の升目。細かいほど密に詰まるが計算量が増える。
  CELL = 2
  COLUMNS = (VIEWBOX_WIDTH / CELL.to_f).ceil
  # 1行ぶんの升目をすべて立てたビット列(空きを探すビット演算で使う)。
  FULL_ROW = (1 << COLUMNS) - 1

  # 本文と同じ字間(tokens.css の --tracking)。幅の見積もりに入れないと、
  # 密に詰めたときに字が隣へはみ出す。
  TRACKING = 0.03

  # 字面が上下へ伸びる量(級数に対する比)。**語ごとに変える**のが要点で、
  # 一律 1.08 で確保していた頃は、欧文だけの語(「NTT」「DS」)が実際の 1.5 倍の高さを
  # 押さえてしまい、そのぶん図がすかすかになっていた。
  # 和文はほぼ全角の枠いっぱいに組まれる。欧文は大文字でも 0.72 ほどしかなく、
  # 下へ伸びるのは g p q y j と丸括弧・カンマだけ。
  ASCENT_FULLWIDTH = 0.88
  ASCENT_LATIN_TALL = 0.75  # b d f h i k l t などアセンダを持つ小文字
  ASCENT_LATIN_CAP = 0.72   # 大文字・数字
  ASCENT_LATIN_X = 0.55     # x ハイトだけで収まる小文字
  DESCENT_FULLWIDTH = 0.12
  DESCENT_LATIN = 0.21
  DESCENT_NONE = 0.02

  LATIN_TALL = /[bdfhiklt]/
  LATIN_DESCENDER = /[gjpqy(),;]/

  # 欧文の字幅(級数に対する比)。A〜Z / a〜z の順。
  # 環境ごとに書体が違うので、UI 書体の中では広い部類(DejaVu Sans)の値を採り、
  # 狭い書体の環境では余白側へ振れるようにしている。
  UPPERCASE_WIDTHS = [
    0.72, 0.69, 0.70, 0.77, 0.63, 0.58, 0.78, 0.75, 0.30, 0.30, 0.68, 0.56, 0.90,
    0.75, 0.79, 0.60, 0.79, 0.70, 0.65, 0.62, 0.73, 0.69, 1.00, 0.69, 0.62, 0.63
  ].freeze
  LOWERCASE_WIDTHS = [
    0.61, 0.64, 0.55, 0.64, 0.61, 0.35, 0.64, 0.63, 0.28, 0.28, 0.58, 0.28, 0.97,
    0.63, 0.61, 0.64, 0.64, 0.41, 0.52, 0.39, 0.63, 0.59, 0.82, 0.59, 0.59, 0.52
  ].freeze
  DIGIT_WIDTH = 0.64
  SYMBOL_WIDTH = 0.45

  # 語どうしの余白。級数に対する比で持つ(升目数で固定すると、小さい語ばかりに
  # なったときに余白だけが場所を食う)。**余白が見えないくらい詰める**指示なので、
  # ここはほぼ 0 にし、実際の隙間は升目(2px)への丸めぶんに任せる。
  GAP_RATIO = 0.02

  # 1語あたりに見る行数(無作為)。行ごとに「幅が収まる左端」をビット演算で一度に出し、
  # その中から無作為に1つ選ぶ。列を1つずつ当たるより桁違いに安く、空きも取りこぼさない。
  ROW_SAMPLES = 32

  # 配置が毎回同じになるよう種を固定する。
  SEED = 20260811

  # 語ごとの色(tokens.css の --cloud-1〜8)の数。
  # 割り当ては語そのものから決めるので、収録が増えても同じ語は同じ色のままになる。
  # String#hash はプロセスごとに変わる(起動のたびに色が入れ替わる)ので使わない。
  PALETTE_SIZE = 8

  # 配置済みの1語。x/y は文字の左下(SVG の text の基準点)。
  # 字面の矩形は (x, top_y) を左上とする width × height(ベースラインは矩形の途中を通る)。
  Placed = Data.define(:text, :count, :weight, :font_size, :x, :y, :top_y, :width, :height,
                       :palette, :top) do
    def top? = top
  end

  # 配置の結果。描画側は height を viewBox に使う。
  Layout = Data.define(:items, :height) do
    def any? = items.any?
  end

  def self.place(entries) = new(entries).place

  # 同じ入力なら結果も同じなので、直前の結果を1つだけ覚えておく。
  # 詰め直すと実測 400ms 前後(100件)かかり、統計ページの表示だけで丸ごと1回分を食う。
  # 入力(語と件数)が変わったら作り直すので、集計ファイルを差し替えるテストでも取り違えない。
  def self.layout(entries)
    key = Array(entries).map { |entry| [ entry.text, entry.count ] }
    return @layout if @layout && @layout_key == key

    @layout_key = key
    @layout = place(entries)
  end

  def initialize(entries)
    @entries = Array(entries)
  end

  # 全語が入るまで高さを広げ、入ったら入る限界まで詰め直す。
  # 1語も捨てないことを優先する(捨てると集計の一部が黙って消え、注記の件数とも食い違う)。
  def place
    boxes = build_boxes
    return Layout.new(items: [], height: MIN_VIEWBOX_HEIGHT) if boxes.empty?

    height = initial_height(boxes)
    items = nil

    MAX_GROWTH_STEPS.times do
      items = pack(boxes, height)
      break if items.size == boxes.size

      items = nil
      height = (height * GROWTH).ceil
    end

    # ここまでで入らなければ、最後の結果をそのまま返す(実データでは起きない)。
    return Layout.new(items: pack(boxes, height), height: height) if items.nil?

    height, items = tighten(boxes, height, items)
    Layout.new(items: items, height: height)
  end

  private

  # 「入らない高さ」と「入る高さ」の間を二分探索して、入る中でいちばん低い高さを採る。
  # 詰め方は乱数に左右されるので、見積もりを1回信じるだけでは字面が 59〜69% で暴れる。
  def tighten(boxes, height, items)
    low = [ minimum_height(boxes), MIN_VIEWBOX_HEIGHT ].max

    SEARCH_STEPS.times do
      break if height - low <= HEIGHT_EPSILON

      middle = (low + height) / 2
      packed = pack(boxes, middle)
      if packed.size == boxes.size
        height = middle
        items = packed
      else
        low = middle + 1
      end
    end

    [ height, items ]
  end

  # 語ごとの級数と、当たり判定に使う升目の大きさを先に出す。
  def build_boxes
    @entries.sort_by { |entry| -entry.weight }.map do |entry|
      font_size = font_size_for(entry)
      gap = font_size * GAP_RATIO
      ascent, descent = vertical_metrics(entry.text)
      {
        entry: entry,
        font_size: font_size,
        gap: gap,
        ascent: ascent * font_size,
        width_cells: cells(text_width(entry.text, font_size) + gap),
        height_cells: cells(((ascent + descent) * font_size) + gap)
      }
    end
  end

  # 外接矩形の総面積を目安の充填率で割って、必要な高さを見積もる。
  def initial_height(boxes)
    [ (box_area(boxes) / (VIEWBOX_WIDTH * TARGET_FILL)).ceil, MIN_VIEWBOX_HEIGHT ].max
  end

  # 外接矩形を隙間なく敷き詰めたときの高さ。これ未満は面積からして絶対に入らない。
  def minimum_height(boxes) = (box_area(boxes) / VIEWBOX_WIDTH.to_f).ceil

  def box_area(boxes)
    boxes.sum { |box| box[:width_cells] * box[:height_cells] } * CELL * CELL
  end

  # 大きい順に置いていく(先に置いた大きい語の隙間へ、あとの小さい語が入り込む)。
  # 最頻の1語だけは中心に据え、残りはばらばらに散らす(オーナー指示 2026-09-10)。
  def pack(boxes, height)
    total_rows = (height / CELL.to_f).ceil
    rows = Array.new(total_rows, 0) # 各行の占有状況をビットで持つ
    random = Random.new(SEED)

    boxes.each_with_index.filter_map do |box, index|
      next if box[:width_cells] > COLUMNS || box[:height_cells] > total_rows

      spot = (center_spot(rows, box, total_rows) if index.zero?) ||
             find_spot(rows, box[:width_cells], box[:height_cells], random, total_rows)
      next unless spot

      occupy(rows, spot, box[:width_cells], box[:height_cells])
      build_placed(box, spot)
    end
  end

  # 中心に据えるときの位置。盤面が空の1語目に使うので必ず空いているが、
  # 万一ふさがっていれば nil を返して通常の探索に任せる。
  def center_spot(rows, box, total_rows)
    column = (COLUMNS - box[:width_cells]) / 2
    row = (total_rows - box[:height_cells]) / 2
    return nil if column.negative? || row.negative?

    mask = (1 << box[:width_cells]) - 1
    free?(rows, column, row, mask, box[:height_cells]) ? [ column, row ] : nil
  end

  # 級数は頻度の位置(0.0〜1.0)をそのまま大きさに写す。
  def font_size_for(entry)
    (MIN_FONT_SIZE + (entry.weight * (MAX_FONT_SIZE - MIN_FONT_SIZE))).round(1)
  end

  # 日本語の全角文字はほぼ正方形なので、字数 × 級数で幅を見積もれる。
  # 欧文は字ごとに幅が違うので LATIN 幅表を引く(「大文字は 0.62」のような平均で見積もると、
  # 幅の広い字が並ぶ「ROCK」が隣の語へ 1 字ぶん食い込む。余白をほぼ 0 にした組みでは
  # この見積もりの甘さがそのまま重なりになる)。
  def text_width(text, font_size)
    units = text.each_char.sum { |char| char_width(char) }
    (units + (text.length * TRACKING)) * font_size
  end

  def char_width(char)
    case char
    when /[ -~]/ then latin_width(char)
    when /[｡-ﾟ]/ then 0.5 # 半角カナ
    else 1.0
    end
  end

  def latin_width(char)
    code = char.ord
    case code
    when 65..90 then UPPERCASE_WIDTHS[code - 65]
    when 97..122 then LOWERCASE_WIDTHS[code - 97]
    when 48..57 then DIGIT_WIDTH
    else SYMBOL_WIDTH
    end
  end

  def cells(length) = (length / CELL.to_f).ceil

  # 語がベースラインの上下へどれだけ伸びるかを、含まれる文字から決める。
  def vertical_metrics(text)
    ascent = DESCENT_NONE
    descent = DESCENT_NONE

    text.each_char do |char|
      if char.match?(/[ -~]/)
        ascent = [ ascent, latin_ascent(char) ].max
        descent = [ descent, DESCENT_LATIN ].max if char.match?(LATIN_DESCENDER)
      else
        # 半角カナも含め、全角として扱う
        ascent = [ ascent, ASCENT_FULLWIDTH ].max
        descent = [ descent, DESCENT_FULLWIDTH ].max
      end
    end

    [ ascent, descent ]
  end

  def latin_ascent(char)
    if char.match?(/[A-Z0-9]/) then ASCENT_LATIN_CAP
    elsif char.match?(LATIN_TALL) then ASCENT_LATIN_TALL
    else ASCENT_LATIN_X
    end
  end

  # 無作為に選んだ行から候補を集め(語をばらけさせるため)、そのうち
  # **いちばん詰まる位置**を選ぶ。1つも空きが無ければ総当たりで探す。
  #
  # 先着で決めていた頃は、隙間だらけの位置にも平気で置いて図がすかすかになっていた
  # (字面 53% → 77%)。最後に総当たりを残すのは、盤面がほぼ埋まったあとの小さい語が
  # 「空きがあるのに引けない」で捨てられるのを防ぐため(実データで 60 件中 23 件が落ちていた)。
  def find_spot(rows, width_cells, height_cells, random, total_rows)
    max_column = COLUMNS - width_cells
    max_row = total_rows - height_cells
    return nil if max_column.negative? || max_row.negative?

    mask = (1 << width_cells) - 1
    best = nil
    best_score = -1

    ROW_SAMPLES.times do
      row = random.rand(max_row + 1)
      free = free_columns(rows, row, width_cells, height_cells)
      next if free.zero?

      column = random_free_column(free, random, max_column)
      score = contact_score(rows, column, row, mask, width_cells, height_cells, total_rows)
      next unless score > best_score

      best_score = score
      best = [ column, row ]
    end

    best || scan_spot(rows, max_row, width_cells, height_cells, random)
  end

  # 空いている左端の候補(ビット列)から1つ選ぶ。無作為な列から右へ最初の空きを採り、
  # 右に無ければ左端の空きへ回る(候補の数を数えずに済むので安い)。
  def random_free_column(free, random, max_column)
    start = random.rand(max_column + 1)
    shifted = free >> start
    return start + lowest_bit_index(shifted) unless shifted.zero?

    lowest_bit_index(free)
  end

  # その位置に置いたとき、上下左右がどれだけ既存の語(と紙の縁)に接するか。
  # 接する升目が多いほど隙間を残さない置き方になる。
  def contact_score(rows, column, row, mask, width_cells, height_cells, total_rows)
    span = mask << column
    score = 0
    score += row.zero? ? width_cells : count_bits(rows[row - 1] & span)
    bottom = row + height_cells
    score += bottom >= total_rows ? width_cells : count_bits(rows[bottom] & span)

    left = column.zero? ? nil : (1 << (column - 1))
    right = (column + width_cells) >= COLUMNS ? nil : (1 << (column + width_cells))
    height_cells.times do |offset|
      line = rows[row + offset]
      score += 1 if left.nil? || line.anybits?(left)
      score += 1 if right.nil? || line.anybits?(right)
    end

    score
  end

  def count_bits(value) = value.zero? ? 0 : value.to_s(2).count("1")

  # 総当たりで空きを探す。無作為な行から始めて一周するのは、
  # 無作為で当たらなかった語がどれも上端へ寄って、下だけ空くのを避けるため。
  def scan_spot(rows, max_row, width_cells, height_cells, random)
    offset = random.rand(max_row + 1)
    (0..max_row).each do |index|
      row = (offset + index) % (max_row + 1)
      column = leftmost_free_column(rows, row, width_cells, height_cells)
      return [ column, row ] if column
    end
    nil
  end

  # 行 row から height_cells 行ぶんを重ね、幅 width_cells が収まる左端の位置を
  # すべてビット列で返す。free &= free >> 1 を幅-1 回繰り返すと
  # 「そこから幅ぶん全部空き」の位置だけが残るので、列を1つずつ試さずに1行を一度で判定できる
  # (語を増やしたときの重さが桁違いに変わる)。
  def free_columns(rows, row, width_cells, height_cells)
    blocked = 0
    height_cells.times { |offset| blocked |= rows[row + offset] }
    free = ~blocked & FULL_ROW
    (width_cells - 1).times do
      free &= free >> 1
      break if free.zero?
    end
    free
  end

  def leftmost_free_column(rows, row, width_cells, height_cells)
    free = free_columns(rows, row, width_cells, height_cells)
    free.zero? ? nil : lowest_bit_index(free)
  end

  def lowest_bit_index(value) = (value & -value).bit_length - 1

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

  # 語から色の番号(1〜PALETTE_SIZE)を決める。CRC32 なのでプロセスをまたいでも同じ。
  def palette_for(text) = (Zlib.crc32(text) % PALETTE_SIZE) + 1

  def build_placed(box, spot)
    column, row = spot
    entry = box[:entry]
    half_gap = box[:gap] / 2
    top_y = (row * CELL) + half_gap
    ascent, descent = vertical_metrics(entry.text)
    Placed.new(
      text: entry.text, count: entry.count, weight: entry.weight, font_size: box[:font_size],
      x: ((column * CELL) + half_gap).round(1),
      top_y: top_y.round(1),
      # SVG の text はベースライン基準。字面の上端から、上に伸びる分だけ下げる。
      y: (top_y + box[:ascent]).round(1),
      width: text_width(entry.text, box[:font_size]).round(1),
      height: ((ascent + descent) * box[:font_size]).round(1),
      palette: palette_for(entry.text),
      top: entry.top?
    )
  end
end
