# 単語の共有カード(og:image、1200×630)を組む値オブジェクト。
#
# 体裁は既定カード public/og-default.png(script/og_default.py)と同じ作りで、長い言葉の壁(ShareCardWall)の上に
# 札(白の面＋墨の枠＋角)を置く(docs/design.md §5.1)。札の左の袖に 読みの五十音円環と文字数、
# 右の本体に 表層形 → 読み → 説明 → ジャンル・品詞の札 を積む。
# 英字の標識は置かない(サイトでも英字の標識をやめた流れと、SNS のサムネイルでは細かい字が読めないため。2026-11-06)。
# ここで決めるのは寸法と文字の組みまでで、SVG は share_cards/word.svg.erb が描き、
# PNG に焼くのは ShareCardRenderer。
# 種別: 値オブジェクト（DB に触れない）。
class WordShareCard
  WIDTH = 1200
  HEIGHT = 630

  # 札の外周(上下左右)と、袖と本体を分ける柱。札の角は既定カードの RADIUS と同じ 12px。
  FRAME_TOP = 66
  FRAME_BOTTOM = 564
  FRAME_LEFT = 76
  PILLAR = 430 # 袖と本体を分ける柱
  FRAME_RIGHT = 1124
  FRAME_RADIUS = 12
  FRAME_MIDDLE = (FRAME_TOP + FRAME_BOTTOM) / 2.0 # 円環と本体の文字は、どちらも枠の上下の中央にそろえる
  # 札の上下の枠から本体の文字までに最低限空ける。長い語で入りきらないときは、説明・札を減らしてこの余白を守る。
  BLOCK_MARGIN = 36

  # 本体の文字の左端と、行が伸びてよい幅(柱と札の右の枠から 44px ずつ空ける)。
  TEXT_LEFT = 474
  TEXT_WIDTH = 606
  # 字間(em)。サイトは和文を palt で詰めてから開ける(見出し 0.06em・本文 0.08em。docs/design.md §2)が、
  # librsvg では palt を掛けられない(ShareCardTypesetter の冒頭)。値だけを移すとかなが 1 字ごとに 0.1em ほど開いて見えるので、
  # 詰めずに組んでもサイトと同じ幅になる字間にする(2026-11-05 に公開語の表層形と読みで、
  # 「palt＋サイトの字間」と同じ幅になる字間を語ごとに求めた中央値。表層形は Bold で測った)。
  # 説明は読みと同じ和文の本文なので、読みと同じ字間にする。
  SURFACE_TRACKING = 0.0
  READING_TRACKING = -0.03
  MEANING_TRACKING = -0.03

  # 表層形・読み・説明の組みの候補。短い語は 1 行で大きく、長い語は行を増やして縮める。
  SURFACE_STEPS = [
    ShareCardTypesetter::Step.new(lines: 1, max: 64, min: 56),
    ShareCardTypesetter::Step.new(lines: 2, max: 56, min: 42),
    ShareCardTypesetter::Step.new(lines: 3, max: 46, min: 36),
    ShareCardTypesetter::Step.new(lines: 4, max: 38, min: 30)
  ].freeze
  READING_STEPS = [
    ShareCardTypesetter::Step.new(lines: 1, max: 24, min: 18),
    ShareCardTypesetter::Step.new(lines: 2, max: 22, min: 16),
    ShareCardTypesetter::Step.new(lines: 3, max: 16, min: 14)
  ].freeze
  # 説明は 2 行まで。サムネイルで読める大きさ(24px 以上)を割るなら、末尾を「…」で落とす。
  MEANING_LINES = 2
  MEANING_MAX = 26
  MEANING_MIN = 24

  # 縦の割り付け。行送りは級数に対する比、和文の字面の上端・下端はベースラインからの比。
  # 表層形 → 読み の字面どうしの間合い(px)は既定カードの 見出し → 説明 に合わせてある。
  SURFACE_LEADING = 1.4
  READING_LEADING = 1.7
  MEANING_LEADING = 1.45
  # Noto Sans CJK JP の ascender 880 / descender -120。MorphemeCloud の ASCENT_FULLWIDTH / DESCENT_FULLWIDTH と同じ値。
  ASCENT = 0.88
  DESCENT = 0.12
  # 和文の字面(漢字)の縦の中心はベースラインから 0.38em 上(= (ascender − descender) / 2)。札の中で字を縦に中央へ置くのに使う。
  GLYPH_MIDDLE = (ASCENT - DESCENT) / 2.0
  SURFACE_TO_READING = 36
  READING_TO_RULE = 28 # 読みの下端 → 説明の前の細罫
  RULE_TO_NEXT = 18 # 細罫 → 説明(または札)の字面の上端
  MEANING_TO_CHIPS = 24

  # ジャンル・品詞の札(サイトの .tag と同じ、白の面＋墨の枠)。画像は縮小されるので、枠は 2px・角は 10px。
  CHIP_FONT_SIZE = 22
  CHIP_HEIGHT = 42
  CHIP_PADDING = 18
  CHIP_GAP = 12
  CHIP_RADIUS = 10

  # 袖の円環(viewBox 200 を 230px に)と、その下の文字数。どちらも袖の中央にそろえる。
  # Web の shared/_kana_ring_art と同じ図を、share_cards/word.svg.erb が別に組む
  # (座標は KanaRing から取る。2 か所の違いは shared/_kana_ring_art の冒頭にまとめてある)。
  RING_SCALE = 1.15
  RING_CENTER_X = (FRAME_LEFT + PILLAR) / 2.0
  RING_CENTER_Y = 232
  RING_START_RADIUS = 2.6 # 始点の点(viewBox の単位。ring-art__start と同じ)
  # 文字数は単語詳細のレールと同じく、数を墨の太字で立て、単位「字」を小さく添える(docs/design.md §5.4)。
  NUMBER_FONT_SIZE = 104
  NUMBER_UNIT_FONT_SIZE = 38
  NUMBER_BASELINE = 482
  NUMBER_UNIT_GAP = 6

  Line = Data.define(:text, :y)
  # 札 1 枚。x・y は札の左上、text_x・text_y は字のベースライン(px)。
  Chip = Data.define(:text, :x, :y, :width, :text_x, :text_y)

  def initialize(word)
    @word = word
    @sense = word.primary_sense
  end

  # 読みが無い(語義が無い)語は円環も文字数も描けないので、既定のカードに任せる。
  def drawable?
    @sense&.reading.present?
  end

  # この環境でカードを焼けるか(描ける語で、rsvg-convert と日本語の書体がある)。
  # 詳細ページの og:image(WordsHelper#word_share_card)と、カードの配信(Words::ShareCardsController)が
  # この 1 つの判定を使う。焼けなければ両方とも既定のカード(SiteUrl::DEFAULT_OG_IMAGE_PATH)に回す。
  def renderable? = drawable? && ShareCardRenderer.available?

  def surface = @word.surface
  def reading = @sense.reading
  def reading_length = @sense.reading_length || reading.length
  def meaning = @sense.meaning.to_s

  def svg
    @svg ||= ApplicationController.render(template: "share_cards/word", formats: [ :svg ], layout: false,
                                          locals: { card: self })
  end

  # 描いた SVG から取った版。og:image の URL に付け、見た目が変わったら URL ごと変えて
  # SNS 側のキャッシュを切り替える(語の表記・読みを直したときも、カードの意匠を変えたときも)。
  def digest
    @digest ||= Digest::SHA256.hexdigest(svg).first(16)
  end

  # 背景の壁(既定カードと同じ並び)。
  def wall = ShareCardWall.default

  # --- 本体の文字 ---

  def surface_font_size = surface_layout.font_size
  def surface_tracking = (surface_font_size * SURFACE_TRACKING).round(2)
  def reading_font_size = reading_layout.font_size
  def reading_tracking = (reading_font_size * READING_TRACKING).round(2)
  def meaning_font_size = plan.fetch(:meaning_font_size)
  def meaning_tracking = (meaning_font_size * MEANING_TRACKING).round(2)

  def surface_lines = plan.fetch(:surface)
  def reading_lines = plan.fetch(:reading)
  def meaning_lines = plan.fetch(:meaning)
  # 読みと説明(札)を分ける細罫の y。説明も札も無いときは nil。
  def rule_y = plan.fetch(:rule)
  def chips = plan.fetch(:chips)

  # --- 左の袖: 円環と文字数 ---

  def ring_radius = (KanaRing::RADIUS * RING_SCALE).round(2)
  def ring_start_radius = (RING_START_RADIUS * RING_SCALE).round(2)

  # 読みを読み順に結んだ点(画像の座標)。KanaRing の viewBox(200)を袖の中央へ写す。
  def ring_points
    @ring_points ||= KanaRing.path(reading).map do |node|
      [ ring_coordinate(node.cx, RING_CENTER_X), ring_coordinate(node.cy, RING_CENTER_Y) ]
    end
  end

  def number_text = reading_length.to_s
  def unit_text = I18n.t("words.index.char_unit")

  # 数と単位を、あいだを NUMBER_UNIT_GAP 空けて 1 つの塊として袖の中央に置いたときの、数の左端と単位の左端。
  def number_x
    @number_x ||= (RING_CENTER_X - number_unit_width / 2.0).round(1)
  end

  def unit_x
    (number_x + number_width + NUMBER_UNIT_GAP).round(1)
  end

  private

  def surface_layout
    @surface_layout ||= ShareCardTypesetter.new(surface, width: TEXT_WIDTH, tracking: SURFACE_TRACKING, bold: true)
                                           .fit(SURFACE_STEPS)
  end

  def reading_layout
    @reading_layout ||= ShareCardTypesetter.new(reading, width: TEXT_WIDTH, tracking: READING_TRACKING).fit(READING_STEPS)
  end

  # 説明を lines 行までに組む(1 行で収まれば 1 行。収まらなければ末尾を「…」で落とす)。説明が無ければ行は無い。
  def meaning_layout(lines)
    @meaning_layouts ||= {}
    @meaning_layouts[lines] ||=
      if lines.zero?
        ShareCardTypesetter::Layout.new(lines: [], font_size: MEANING_MAX)
      else
        steps = (1..lines).map { |count| ShareCardTypesetter::Step.new(lines: count, max: MEANING_MAX, min: MEANING_MIN) }
        ShareCardTypesetter.new(meaning, width: TEXT_WIDTH, tracking: MEANING_TRACKING).fit(steps)
      end
  end

  def number_width = text_width(number_text, NUMBER_FONT_SIZE, bold: true)
  def number_unit_width = number_width + NUMBER_UNIT_GAP + NUMBER_UNIT_FONT_SIZE # 単位「字」は全角 1 字

  def text_width(text, font_size, bold: false)
    ShareCardTypesetter.new(text, width: 1, tracking: 0, bold:).width_em * font_size
  end

  # ジャンルと品詞の名前。付いていないものは出さない。
  def chip_labels = [ @sense.genre&.name, @sense.part_of_speech&.name ].compact_blank

  # 本体の組み。表層形の字面の上端から、いちばん下の要素の下端までをひとかたまりとして、札の上下の中央に置く。
  # 入りきらない長い語(表層形が 4 行になるなど)は、説明の 2 行・札 → 説明の 2 行 → 説明の 1 行 → 説明なし、の順に減らす。
  def plan
    @plan ||= begin
      available = FRAME_BOTTOM - FRAME_TOP - 2 * BLOCK_MARGIN
      candidates = [ [ meaning_layout(MEANING_LINES), true ], [ meaning_layout(MEANING_LINES), false ],
                     [ meaning_layout(1), false ], [ meaning_layout(0), false ] ]
      plans = candidates.map { |layout, with_chips| compose(layout, with_chips) }
      plans.find { |candidate| candidate.fetch(:height) <= available } || plans.last
    end
  end

  # layout(説明の組み)と with_chips(札を出すか)で、相対の縦位置を決め、札の上下の中央へ寄せた結果を返す。
  def compose(layout, with_chips)
    surface_ys = surface_layout.lines.each_index.map { |index| index * surface_font_size * SURFACE_LEADING }
    reading_top = surface_ys.last + DESCENT * surface_font_size + SURFACE_TO_READING + ASCENT * reading_font_size
    reading_ys = reading_layout.lines.each_index.map { |index| reading_top + index * reading_font_size * READING_LEADING }
    cursor = reading_ys.last + DESCENT * reading_font_size

    labels = with_chips ? chip_labels : []
    rule = (cursor + READING_TO_RULE if layout.lines.any? || labels.any?)
    cursor = rule if rule

    meaning_ys = []
    if layout.lines.any?
      first = cursor + RULE_TO_NEXT + ASCENT * layout.font_size
      meaning_ys = layout.lines.each_index.map { |index| first + index * layout.font_size * MEANING_LEADING }
      cursor = meaning_ys.last + DESCENT * layout.font_size
    end

    chip_top = nil
    if labels.any?
      chip_top = cursor + (meaning_ys.any? ? MEANING_TO_CHIPS : RULE_TO_NEXT)
      cursor = chip_top + CHIP_HEIGHT
    end

    top = -ASCENT * surface_font_size
    offset = FRAME_MIDDLE - (top + cursor) / 2.0
    place = ->(texts, ys) { texts.zip(ys).map { |text, y| Line.new(text:, y: (y + offset).round(1)) } }
    {
      height: cursor - top,
      surface: place.(surface_layout.lines, surface_ys),
      reading: place.(reading_layout.lines, reading_ys),
      rule: rule && (rule + offset).round,
      meaning: place.(layout.lines, meaning_ys),
      meaning_font_size: layout.font_size,
      chips: chip_top ? chips_at(labels, (chip_top + offset).round(1)) : []
    }
  end

  # 札を左から並べる。本体の幅に収まらなくなった札は出さない。
  def chips_at(labels, top)
    x = TEXT_LEFT
    labels.filter_map do |label|
      width = (text_width(label, CHIP_FONT_SIZE) + 2 * CHIP_PADDING).round(1)
      next if x + width > TEXT_LEFT + TEXT_WIDTH

      chip = Chip.new(text: label, x: x, y: top, width: width, text_x: (x + CHIP_PADDING).round(1),
                      text_y: (top + CHIP_HEIGHT / 2.0 + GLYPH_MIDDLE * CHIP_FONT_SIZE).round(1))
      x += width + CHIP_GAP
      chip
    end
  end

  def ring_coordinate(value, center)
    ((value - KanaRing::CENTER) * RING_SCALE + center).round(2)
  end
end
