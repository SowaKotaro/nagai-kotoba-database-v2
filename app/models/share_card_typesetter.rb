# 共有カード(WordShareCard)の文字を行に割り、枠の幅に収まる級数を選ぶ値オブジェクト。
#
# rsvg-convert は SVG の文字を折り返さないので、行の割り方と級数はこちらで決めて渡す。
# 字幅は本番で焼くときの書体 Noto Sans CJK JP(Regular)の送り幅で見積もる:
# 全角(かな・漢字・全角記号)は 1em、半角の英数字・記号は ASCII_ADVANCES(実フォントから採寸)、
# 半角カナは 0.5em。librsvg の字間(letter-spacing)は字と字のあいだにだけ効く(実測)。
#
# 割り方:
#   - 行頭に置かない字(、。ー 小書きかな 閉じ括弧 など)の前、行末に置かない字(開き括弧)の後、
#     英単語・数字の途中、WORD_JOINER を挟んだ字のあいだでは割らない。
#   - 組みの候補(Step)を「割りやすい所だけで割る」で先頭から試し、どれも収まらなければ
#     「どこで割ってもよい(割りにくい所で割る回数はなるべく少なく)」でもう一度試す。
#     割りやすい所 = 空白・区切り記号の後、英字⇔和字・カタカナ⇔漢字の変わり目、助詞の後。
#     行の長さだけでそろえると「ピン / ボール」のように語の途中で割れるため。
#   - 同じ条件の割り方が複数あれば、いちばん長い行が最も短いもの(行の長さがそろうもの)を選ぶ。
# 種別: 値オブジェクト（DB に触れない）。
class ShareCardTypesetter
  # 組んだ結果。lines は各行の文字列、font_size は級数(px)。
  Layout = Data.define(:lines, :font_size)
  # 組みの候補。lines 行に割り、級数は max を上限に、幅に合わせて min まで縮めてよい。
  Step = Data.define(:lines, :max, :min)

  # U+2060 WORD JOINER。この字を挟んだ前後では割らない。「（13文字）」のような塊を呼び出し側が守るときに挟む。
  # 見えない字なので、ソースには字そのものを書かず符号位置から作る。
  WORD_JOINER = [ 0x2060 ].pack("U").freeze
  # 最後の候補でも収まらないときに、末尾を落として付ける記号。
  ELLIPSIS = "…".freeze

  # U+0020〜U+007E の送り幅(1000 = 1em)。Noto Sans CJK JP Regular の実測値。
  ASCII_ADVANCES = [
    224, 323, 474, 555, 555, 921, 680, 278, 338, 338, 467, 555, 278, 347, 278, 392, # 空白 ! " # $ % & ' ( ) * + , - . /
    555, 555, 555, 555, 555, 555, 555, 555, 555, 555, 278, 278, 555, 555, 555, 474, # 0-9 : ; < = > ?
    946, 608, 657, 638, 688, 589, 552, 689, 728, 293, 535, 646, 543, 812, 723, 742, # @ A-O
    633, 742, 635, 596, 599, 721, 575, 878, 573, 531, 603, 338, 392, 338, 555, 559, # P-Z [ \ ] ^ _
    606, 563, 618, 510, 620, 554, 325, 564, 607, 275, 275, 552, 284, 926, 610, 606, # ` a-o
    620, 620, 388, 468, 377, 607, 521, 802, 498, 521, 475, 338, 270, 338, 555       # p-z { | } ~
  ].freeze
  HALFWIDTH_KANA_ADVANCE = 0.5
  # アクセント付きの欧文字(Latin-1 補助・拡張)。和文書体の中では半角のプロポーショナルなので平均値で見積もる。
  LATIN_EXTENDED_ADVANCE = 0.6

  # 行頭に置かない字(この字の前では割らない)。
  NO_BREAK_BEFORE = "、。，．・：；？！＝ー）」』】〕〉》…‥〜ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ々ゝゞヽヾ&＆)]},.:;!?%".chars.to_set.freeze
  # 行末に置かない字(この字の後では割らない)。前で割るのは割りやすい。
  OPENING_BRACKETS = "（「『【〔〈《([{".chars.to_set.freeze
  CLOSING_BRACKETS = "）」』】〕〉》)]}".chars.to_set.freeze
  # 区切りの記号。この後は割りやすい。
  SEPARATORS = "、。・：！？＝／&＆!?/".chars.to_set.freeze
  # 助詞。後ろに漢字・カタカナ・英字が続くなら文節の切れ目とみなす。
  PARTICLES = "のをにはがでとへもや".chars.to_set.freeze
  # 英単語の一部。この字どうしのあいだでは割らない(「Mrs.」「X-MEN」「3D」「Don’t」を割らない)。
  WORD_CHAR = /\A[\p{Latin}0-9.'’\-]\z/
  # 制御文字(改行・タブは squish が空白に寄せたあと)。SVG の XML として不正になるので取り除く。
  CONTROL_CHARS = /[\x00-\x1F\x7F]/

  def initialize(text, width:, tracking:)
    @width = width
    @tracking = tracking
    @chars = []
    @glued = Set.new # この位置の字の前では割らない(WORD_JOINER があった所)
    text.to_s.squish.gsub(CONTROL_CHARS, "").each_grapheme_cluster do |cluster|
      cluster == WORD_JOINER ? @glued << @chars.size : @chars << cluster
    end
    @prefix_advances = @chars.each_with_object([ 0.0 ]) { |char, sums| sums << sums.last + advance(char) }
  end

  # 収まる組みを返す。どの候補にも収まらなければ、最後の候補の最小級数で収まるまで
  # 末尾を落として「…」を付ける。
  def fit(steps)
    return Layout.new(lines: [], font_size: steps.first.max) if @chars.empty?

    first_fitting_layout(steps) || truncated_layout(steps.last)
  end

  protected

  # 割りやすい所だけ → どこでも、の順に候補を試し、最小級数以上で収まった最初の組み(無ければ nil)。
  def first_fitting_layout(steps)
    [ preferred_positions, break_positions ].each do |positions|
      steps.each do |step|
        layout = layout_for(step, positions)
        return layout if layout
      end
    end
    nil
  end

  private

  # positions の中で割って step の行数に組む。最小級数を割る行ができるなら nil。
  # 割ってよい位置が行数に足りない(1 語の英単語など)ときは、割れるだけの行数で組む。
  def layout_for(step, positions)
    lines = [ step.lines, break_positions.size + 1 ].min
    breaks = split(lines, positions, @width.to_f / step.min)
    return unless breaks

    ranges = [ 0, *breaks ].zip([ *breaks, @chars.size ])
    widest = ranges.map { |from, to| line_em(from, to) }.max
    Layout.new(lines: ranges.map { |from, to| @chars[from...to].join.strip },
               font_size: [ step.max, (@width / widest).floor ].min)
  end

  # positions から割り位置を選んで lines 行に割る。どの行も limit(em)に収まる割り方のうち、
  # 割りにくい所で割る回数が最も少なく、同数ならいちばん長い行が最も短いものの割り位置を返す。
  # そう割れなければ nil。
  def split(lines, positions, limit)
    rows = [ { 0 => [ 0, 0.0, nil ] } ] # 行ごとに 割り位置 => [割りにくい回数, いちばん長い行, 直前の割り位置]
    lines.times do |index|
      last_line = index == lines - 1
      previous = rows.last
      rows << (last_line ? [ @chars.size ] : positions).each_with_object({}) do |finish, row|
        # 行の始まりを後ろから見ていき、limit を超えたらそれより前は見ない(行は前に伸ばすほど長い)
        previous.reverse_each do |start, (awkward, widest)|
          next if start >= finish

          width = line_em(start, finish)
          break if width > limit

          awkward += 1 unless last_line || preferred_positions_set.include?(finish)
          widest = width if width > widest
          best = row[finish]
          if best.nil? || awkward < best[0] || (awkward == best[0] && widest < best[1])
            row[finish] = [ awkward, widest, start ]
          end
        end
      end
    end
    trace_breaks(rows) if rows.last.key?(@chars.size)
  end

  # 最終行の末尾から「直前の割り位置」をたどって、割り位置を先頭から並べる。
  def trace_breaks(rows)
    position = @chars.size
    (rows.size - 1).downto(1).filter_map do |level|
      position = rows[level].fetch(position).last
      position if position.positive?
    end.reverse
  end

  # 割ってよい位置(その位置の字の前で行を改める)。
  def break_positions
    @break_positions ||= (1...@chars.size).select { |position| breakable?(position) }
  end

  def preferred_positions
    @preferred_positions ||= break_positions.select { |position| preferred_break?(position) }
  end

  def preferred_positions_set
    @preferred_positions_set ||= preferred_positions.to_set
  end

  def breakable?(position)
    before = @chars[position - 1]
    after = @chars[position]
    return false if @glued.include?(position) || after == " "
    return true if before == " "
    return false if word_char?(before) && word_char?(after)

    !NO_BREAK_BEFORE.include?(after) && !OPENING_BRACKETS.include?(before)
  end

  def preferred_break?(position)
    before = @chars[position - 1]
    after = @chars[position]
    return true if before == " " || SEPARATORS.include?(before)
    return true if CLOSING_BRACKETS.include?(before) || OPENING_BRACKETS.include?(after)

    before_script = script(before)
    after_script = script(after)
    return false unless before_script && after_script
    return after_script != :hiragana if PARTICLES.include?(before)

    # 送り仮名(漢字→ひらがな)や「抱き / 合う」(ひらがな→漢字)の切れ目は割りやすいとみなさない
    before_script != after_script && ![ before_script, after_script ].include?(:hiragana)
  end

  def script(char)
    if char.match?(/\A[A-Za-z]/) then :latin
    elsif char.match?(/\A\p{Hiragana}/) then :hiragana
    elsif char.match?(/\A[\p{Katakana}ー]/) then :katakana
    elsif char.match?(/\A\p{Han}/) then :kanji
    end
  end

  def word_char?(char) = char.match?(WORD_CHAR)

  # from〜to の字を 1 行に置いたときの幅(em)。行末の空白は数えない。
  def line_em(from, to)
    to -= 1 while to > from && @chars[to - 1] == " "
    count = to - from
    return 0.0 unless count.positive?

    @prefix_advances[to] - @prefix_advances[from] + @tracking * (count - 1)
  end

  def advance(char)
    code = char.ord
    if code.between?(0x20, 0x7E) then ASCII_ADVANCES[code - 0x20] / 1000.0
    elsif code.between?(0xFF61, 0xFF9F) then HALFWIDTH_KANA_ADVANCE
    elsif code.between?(0x80, 0x24F) then LATIN_EXTENDED_ADVANCE
    else 1.0
    end
  end

  # 末尾を落として「…」を付け、step の最小級数で収まる最長の形を二分探索で探す。
  def truncated_layout(step)
    overflowing = (1...@chars.size).bsearch { |count| truncated(count).first_fitting_layout([ step ]).nil? }
    kept = overflowing ? overflowing - 1 : @chars.size - 1
    truncated(kept).first_fitting_layout([ step ]) || Layout.new(lines: [ ELLIPSIS ], font_size: step.min)
  end

  # 先頭 count 字に「…」を付けた組み手。WORD_JOINER の位置は引き継ぐ。
  def truncated(count)
    kept = @chars.first(count).each_with_index.map { |char, index| @glued.include?(index) ? WORD_JOINER + char : char }
    self.class.new("#{kept.join.rstrip}#{ELLIPSIS}", width: @width, tracking: @tracking)
  end
end
