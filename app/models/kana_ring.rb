# 五十音を単一の「円環」に配置し、ある読みを一筆書きの朱線(印章)として描くための値オブジェクト。
#
# 配置:
#   - 基本46字(ア〜ン)を五十音順で外周の円上に等間隔で並べる(頂点=ア、時計回りにン)。
#   - 撥音「ン」は五十音順の末尾なので、頂点アのすぐ手前(左上)に来る。
#
# 読みの畳み方は KanaRow に合わせる(しりとり慣習: 濁音・半濁音は清音へ、小書きは大書きへ、
# ヴ→ウ、ヰ/ヱ→イ/エ)。長音符「ー」など基本46字に載らない文字は経路から除く。
# 座標は 200x200 の viewBox 前提。
class KanaRing
  VIEWBOX = 200
  CENTER = 100.0
  RADIUS = 82.0

  # 円周に並べる字と順序(ア〜ン)。KanaRow::BASE_46 がそのまま五十音順。
  ORDER = KanaRow::BASE_46
  SIZE = ORDER.size

  # 円環上の1点(基本字・五十音順の位置・中心座標)。
  Node = Data.define(:char, :index, :cx, :cy)

  # 基本字 => Node。読み込み時に一度だけ算出して凍結する。
  NODES_BY_CHAR = ORDER.each_with_index.to_h { |char, index|
    angle = (-90 + index * 360.0 / SIZE) * Math::PI / 180
    cx = (CENTER + RADIUS * Math.cos(angle)).round(2)
    cy = (CENTER + RADIUS * Math.sin(angle)).round(2)
    [ char, Node.new(char: char, index: index, cx: cx, cy: cy) ]
  }.freeze

  # 背景に敷く五十音全字の点(基本46字、五十音順)。
  def self.nodes
    NODES_BY_CHAR.values
  end

  # 読みを1文字ずつ基本字へ畳み、円環上の点を読み順に並べて返す(印章の折れ線)。
  # 基本46字に載らない文字(長音符など)は経路から除く。
  def self.path(reading)
    reading.to_s.each_char.filter_map { |char| node_for(char) }
  end

  # 経路が通った基本字の集合(点灯させる字の判定に使う)。
  def self.visited_chars(reading)
    path(reading).map(&:char).to_set
  end

  # 遷移エッジ(読み順に結んだ弦)同士が円の内部で交差する回数。
  # 端点を共有するエッジ(隣接・同じ字の再訪)や退化したエッジは交差に数えない。
  def self.crossing_count(reading)
    edges = path(reading).map(&:index).each_cons(2).to_a
    count = 0
    edges.each_with_index do |edge, i|
      edges[(i + 1)..].each do |other|
        count += 1 if cross?(edge, other)
      end
    end
    count
  end

  # 2本の弦が円の内部で交差するか。円周上では、4端点が円環を辿る順で
  # 交互に並ぶ(一方の端点が他方の弧の内側と外側に分かれる)ときだけ交差する。
  def self.cross?(edge, other)
    a, b = edge
    c, d = other
    return false if [ a, b, c, d ].uniq.size < 4

    within_arc?(a, b, c) != within_arc?(a, b, d)
  end
  private_class_method :cross?

  # x が、a から b へ +1 方向に辿る弧の内側(両端を除く)にあるか。
  def self.within_arc?(a, b, x)
    offset = (x - a) % SIZE
    offset.positive? && offset < (b - a) % SIZE
  end
  private_class_method :within_arc?

  # 1文字を基本字へ畳んで対応する Node を返す(畳めない文字は nil)。
  def self.node_for(char)
    base = KanaRow.base(char)
    base && NODES_BY_CHAR[base]
  end
  private_class_method :node_for
end
