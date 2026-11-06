# 共有カード(既定・単語ごと)の背景に敷く「長い言葉の壁」の配置を決める値オブジェクト。
#
# 公開している長い言葉を、地の上に淡い墨で何行も、同じ語を繰り返さずに流す。前に置く札(白の面)に隠れない縁だけが見え、
# 「長い言葉がたくさんある」という量感になる(docs/design.md §5.1)。
# 語と配置の数は config/share_card_wall.json にあり、既定カード(script/og_default.py)も同じ並びを描く
# (並べ方の規則は JSON の note。Python 側にも同じ規則を書いているので、変えるときは両方をそろえる)。
# 行頭の x は行ごとに指定する(indents)ので、1 行だけ動かしたいときもほかの行はそのまま。
# 字幅は ShareCardTypesetter の Bold(本番の書体の実測)で見積もる。
# 種別: 値オブジェクト（DB に触れない）。
class ShareCardWall
  CONFIG_PATH = Rails.root.join("config/share_card_wall.json").freeze

  # 壁の 1 語。x は左端、y はベースライン(px)。
  Item = Data.define(:text, :x, :y)

  def self.default = @default ||= new(JSON.parse(CONFIG_PATH.read))

  def initialize(config)
    @config = config
  end

  def font_size = @config.fetch("font_size")
  def fill = @config.fetch("fill")

  # 描く語を、上の行から順に、行の中は左から返す。words の順に 1 語ずつ、右端(width)に届くまで流す
  # (同じ語は繰り返さない。words が足りなければ先頭へ戻る)。
  def items(width: WordShareCard::WIDTH)
    @items ||= {}
    @items[width] ||= build(width).freeze
  end

  private

  def build(width)
    words = @config.fetch("words")
    index = 0
    @config.fetch("rows").times.flat_map do |row|
      baseline = (@config.fetch("first_baseline") + row * @config.fetch("pitch")).round(2)
      x = @config.fetch("indents").fetch(row)
      row_items = []
      while x < width
        text = words[index % words.size]
        row_items << Item.new(text: text, x: x.round(1), y: baseline)
        x += advance(text) + @config.fetch("gap")
        index += 1
      end
      row_items
    end
  end

  def advance(text)
    ShareCardTypesetter.new(text, width: 1, tracking: 0, bold: true).width_em * font_size
  end
end
