# 単語の共有カード(og:image、1200×630)を組む値オブジェクト。
#
# 体裁は既定カード public/og-default.png(script/og_default.py)と同じ格子で、
# 左の袖に読みの五十音円環、右の本体に 表層形 → 読み(文字数) → 罫 → 標識 を積む(docs/design.md §5.1)。
# ここで決めるのは寸法と文字の組みまでで、SVG は share_cards/word.svg.erb が描き、
# PNG に焼くのは ShareCardRenderer。
class WordShareCard
  WIDTH = 1200
  HEIGHT = 630

  # 格子(既定カードと同じ位置)。横罫 2 本は画像の端まで通し、縦罫 3 本は区画の全高に通す。
  FRAME_TOP = 66
  FRAME_BOTTOM = 564
  FRAME_LEFT = 76
  PILLAR = 430 # 袖と本体を分ける柱
  FRAME_RIGHT = 1124
  FRAME_MIDDLE = (FRAME_TOP + FRAME_BOTTOM) / 2.0 # 円環と本体の文字は、どちらも枠の上下の中央にそろえる

  # 本体の文字の左端と、行が伸びてよい幅(柱と額から 44px ずつ空ける)。
  TEXT_LEFT = 474
  TEXT_WIDTH = 606
  # 字間(em)。本文と同じ --tracking。標識は .label-en と同じ 0.04em。
  TRACKING = 0.03
  LABEL_TRACKING = 0.04
  LABEL_FONT_SIZE = 19

  # 表層形と読みの組みの候補。短い語は 1 行で大きく、長い語は行を増やして縮める。
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

  # 縦の割り付け。行送りは級数に対する比、和文の字面の上端・下端はベースラインからの比。
  # 字面どうしの間合い(px)は既定カードの 見出し → 説明 → 罫 → 標識 に合わせてある。
  SURFACE_LEADING = 1.4
  READING_LEADING = 1.7
  ASCENT = 0.88
  DESCENT = 0.12
  SURFACE_TO_READING = 36
  READING_TO_RULE = 44
  RULE_TO_LABEL = 44 # 罫 → 標識 1 行目のベースライン
  LABEL_LEADING = 40

  # 円環は既定カードの印と同じ大きさ(viewBox 200 を 268px に)で、袖の中央に置く。
  RING_SCALE = 1.34
  RING_CENTER_X = (FRAME_LEFT + PILLAR) / 2.0
  RING_CENTER_Y = FRAME_MIDDLE
  RING_START_RADIUS = 2.6 # 始点の点(viewBox の単位。ring-art__start と同じ)

  Line = Data.define(:text, :y)

  def initialize(word)
    @word = word
    @sense = word.word_senses.min_by(&:id)
  end

  # 読みが無い(語義が無い)語は円環も文字数も描けないので、既定のカードに任せる。
  def drawable?
    @sense&.reading.present?
  end

  def surface = @word.surface
  def reading = @sense.reading
  def reading_length = @sense.reading_length || reading.length

  def svg
    @svg ||= ApplicationController.render(template: "share_cards/word", formats: [ :svg ], layout: false,
                                          locals: { card: self })
  end

  # 描いた SVG から取った版。og:image の URL に付け、見た目が変わったら URL ごと変えて
  # SNS 側のキャッシュを切り替える(語の表記・読みを直したときも、カードの意匠を変えたときも)。
  def digest
    @digest ||= Digest::SHA256.hexdigest(svg).first(16)
  end

  # --- 本体の文字 ---

  def surface_font_size = surface_layout.font_size
  def surface_tracking = (surface_font_size * TRACKING).round(2)
  def reading_font_size = reading_layout.font_size
  def reading_tracking = (reading_font_size * TRACKING).round(2)
  def label_tracking = (LABEL_FONT_SIZE * LABEL_TRACKING).round(2)

  def surface_lines = vertical_layout.fetch(:surface)
  def reading_lines = vertical_layout.fetch(:reading)
  def rule_y = vertical_layout.fetch(:rule)
  def label_lines = vertical_layout.fetch(:label)

  # --- 左の袖の円環 ---

  def ring_radius = (KanaRing::RADIUS * RING_SCALE).round(2)
  def ring_start_radius = (RING_START_RADIUS * RING_SCALE).round(2)

  # 読みを読み順に結んだ点(画像の座標)。KanaRing の viewBox(200)を袖の中央へ写す。
  def ring_points
    @ring_points ||= KanaRing.path(reading).map do |node|
      [ ring_coordinate(node.cx, RING_CENTER_X), ring_coordinate(node.cy, RING_CENTER_Y) ]
    end
  end

  private

  def surface_layout
    @surface_layout ||= ShareCardTypesetter.new(surface, width: TEXT_WIDTH, tracking: TRACKING).fit(SURFACE_STEPS)
  end

  # 読みの後ろに文字数を添える。標識の 2 行目(READING / N CHARACTERS)と同じ数を日本語側にも置く
  # (docs/design.md §5.8)。文字数は読みの末尾から離さず、途中でも割らない
  # (「（24文字）」だけが次の行に落ちると、括弧の空きで字下げしたように見える)。
  def reading_layout
    @reading_layout ||= begin
      length = I18n.t("words.share_card.reading_length", count: reading_length)
      text = ([ reading ] + length.chars).join(ShareCardTypesetter::WORD_JOINER)
      ShareCardTypesetter.new(text, width: TEXT_WIDTH, tracking: TRACKING).fit(READING_STEPS)
    end
  end

  def label_texts
    [ URI.parse(Rails.application.config.x.canonical_host).host.upcase,
      I18n.t("labels.en.reading_characters", count: reading_length) ]
  end

  # 表層形の字面の上端から標識の 2 行目までをひとかたまりとして、枠の上下の中央に置く。
  def vertical_layout
    @vertical_layout ||= begin
      surface_ys = surface_layout.lines.each_index.map { |index| index * surface_font_size * SURFACE_LEADING }
      reading_top = surface_ys.last + DESCENT * surface_font_size + SURFACE_TO_READING + ASCENT * reading_font_size
      reading_ys = reading_layout.lines.each_index.map { |index| reading_top + index * reading_font_size * READING_LEADING }
      rule = reading_ys.last + DESCENT * reading_font_size + READING_TO_RULE
      label_ys = [ rule + RULE_TO_LABEL, rule + RULE_TO_LABEL + LABEL_LEADING ]

      top = -ASCENT * surface_font_size
      offset = FRAME_MIDDLE - (top + label_ys.last) / 2.0
      place = ->(texts, ys) { texts.zip(ys).map { |text, y| Line.new(text:, y: (y + offset).round(1)) } }
      {
        surface: place.(surface_layout.lines, surface_ys),
        reading: place.(reading_layout.lines, reading_ys),
        rule: (rule + offset).round,
        label: place.(label_texts, label_ys)
      }
    end
  end

  def ring_coordinate(value, center)
    ((value - KanaRing::CENTER) * RING_SCALE + center).round(2)
  end
end
