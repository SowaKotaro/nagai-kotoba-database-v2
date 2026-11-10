# 検索結果(単語一覧)の各行で、検索条件に当たった箇所を求める。ビューはその箇所を <mark> で囲む(WordsHelper#search_highlighted)。
#
# ハイライトするのは、文字列の一部に当たる条件だけ。
#   - キーワード(q): 表層形・読みの、キーワードに当たる箇所(当たり方の正は KeywordMatch)
#   - 正規表現(regexp): 表層形・読みの、パターンに当たる箇所(当たり方は MySQL に問い合わせる。下記)
#   - 言語学的特徴(linguistic_feature_id): 絞り込んだ特徴の該当部分(表層形は target_start から、読みは target_reading)
#   - ヘボン式ローマ字(rhythm_pattern)・母音(vowel_reading・vowel_transition): 読みのうち、ローマ字・母音の並びで
#     当たった箇所を生んだ字(拍の途中で当たっても字ごと囲む。RhythmPattern.segments で字へ戻す)。表層形は囲まない
#   - 音の成分(dakuten_min など): 読みのうち、数えた字(濁音・半濁音／小書き／長音符。字の集合の正は WordSenseMetrics)
# ジャンル・エンティティなど語全体に付く条件と、文字数などの数の条件はハイライトしない。
# 条件どうしの組み合わせ(AND / OR)によらず、実際に当たった箇所だけを囲む(OR で別の条件だけが当たった行は囲まない)。
#
# 条件ごと(言語学的特徴は付いた該当部分ごと)に当たった箇所を 1 枚の層とし、2 枚以上が重なった字は濃く囲む
# (蛍光ペンの重ね塗り。濃さは 2 段だけ。2026-11-10 オーナー判断)。返すのは Span の並びで、先頭から順に、
# 同じ濃さで続く字は 1 つにまとめる。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class SearchHighlight
  # 正規表現に当たった箇所の前後に挿む目印。REGEXP_REPLACE の置換文字列で、当たった部分($0)を挟む。
  # 表層形・読みに制御文字は入らないので、目印を取り除けば元の文字列に戻る(戻らなければハイライトしない)。
  MATCH_OPEN = "\u0001".freeze
  MATCH_CLOSE = "\u0002".freeze
  # 照合は検索(WordSense.regexp_matching)と同じく列の照合順序で行われるので、大文字小文字の扱いも検索と揃う。
  # Ruby の Regexp で当て直さないのは、MySQL の REGEXP(ICU)と方言がずれるため(SearchRegexp#valid_syntax? と同じ理由)。
  REGEXP_MARKED_READING = "REGEXP_REPLACE(word_senses.reading, ?, " \
                          "CONCAT(CHAR(1 USING utf8mb4), '$0', CHAR(2 USING utf8mb4)))".freeze
  REGEXP_MARKED_SURFACE = "REGEXP_REPLACE(words.surface, ?, " \
                          "CONCAT(CHAR(1 USING utf8mb4), '$0', CHAR(2 USING utf8mb4)))".freeze
  # 音の成分の条件と、数えた字の集合(WordSenseSearch::SOUND_COUNT_FILTERS と同じ 3 つ)。
  SOUND_CHARS = {
    dakuten_min: WordSenseMetrics::DAKUTEN_KANA,
    small_kana_min: WordSenseMetrics::SMALL_KANA,
    chouon_min: WordSenseMetrics::CHOUON
  }.freeze

  # 囲む箇所。range は字の位置の Range、deep は 2 つ以上の条件が重なって当たった箇所か。
  Span = Data.define(:range, :deep)

  # words は一覧に出す語(語義を読み込み済み)。言語学的特徴で絞り込んだときは、語義の word_sense_features も
  # 読み込んでおく(WordsController#entry_row_preloads)。
  def initialize(search, words)
    @search = search
    @words = words
  end

  # 表層形の、囲む箇所。
  def surface(word)
    layers = [ keyword_ranges(word.surface), regexp_marks.dig(:surface, word.id) || [] ]
    layers += feature_senses(word).flat_map do |_sense, features|
      features.map { |feature| feature_surface_ranges(word.surface, [ feature ]) }
    end
    self.class.spans(layers)
  end

  # 読み(一覧の行は同じ読みを 1 回だけ出すので、読みの文字列ごとに求める)の、囲む箇所。
  # 同じ読みの語義が複数あれば、どの語義で当たった箇所も囲む。
  def reading(word, reading)
    senses = word.word_senses.select { |sense| sense.reading == reading }
    layers = [
      keyword_ranges(reading),
      senses.flat_map { |sense| regexp_marks.dig(:reading, sense.id) || [] },
      romaji_ranges(reading),
      vowel_ranges(reading),
      vowel_transition_ranges(reading),
      *sound_ranges(reading)
    ]
    layers += feature_senses(word).flat_map do |sense, features|
      next [] unless sense.reading == reading

      features.map { |feature| feature_reading_ranges(word.surface, reading, [ feature ]) }
    end
    self.class.spans(layers)
  end

  # 層(条件ごとの範囲の並び)を重ねて、囲む箇所の並びにする。2 枚以上の層が重なった字は deep。
  def self.spans(layers)
    layers = layers.map { |ranges| KeywordMatch.merge(ranges) }.reject(&:empty?)
    points = layers.flatten.flat_map { |range| [ range.begin, range.end ] }.uniq.sort
    points.each_cons(2).each_with_object([]) do |(from, to), spans|
      depth = layers.count { |ranges| ranges.any? { |range| range.begin <= from && to <= range.end } }
      next if depth.zero?

      deep = depth >= 2
      if spans.last && spans.last.range.end == from && spans.last.deep == deep
        spans[-1] = Span.new(range: spans.last.range.begin...to, deep: deep)
      else
        spans << Span.new(range: from...to, deep: deep)
      end
    end
  end

  # キーワードが表層形・読みに当たらず、別表記だけに当たった語の、当たった別表記(Issue 72)。
  # 一覧の行に「別表記〈◯◯〉で一致」と添える(なぜ出たのかが自明な行には添えない)。
  def matched_variants(word)
    return [] if @search.q.blank?
    return [] if keyword_ranges(word.surface).any?
    return [] if word.word_senses.any? { |sense| keyword_ranges(sense.reading).any? }

    word.word_senses.flat_map(&:word_sense_variants).select do |variant|
      keyword_ranges(variant.surface).any? || keyword_ranges(variant.reading).any?
    end.uniq(&:surface)
  end

  private

  def keyword_ranges(text) = KeywordMatch.ranges(text, @search.q)

  # ヘボン式ローマ字(rhythm_pattern の部分一致)で当たった、読みの字。照合はキーワードと同じ畳み方(列は ai_ci)。
  def romaji_ranges(reading)
    return [] if @search.rhythm_pattern.blank?

    segments = romaji_segments(reading)
    romaji = segments.map(&:romaji).join
    KeywordMatch.ranges(romaji, @search.rhythm_pattern).filter_map { |range| reading_range(segments, range) }
  end

  # 母音の並び(vowel_pattern の部分一致)で当たった、読みの字。
  def vowel_ranges(reading)
    query = @search.vowel_pattern_query
    return [] if query.blank?

    vowels, owners = vowel_owners(reading)
    KeywordMatch.ranges(vowels, query).filter_map { |range| owner_range(owners, range) }
  end

  # 母音の遷移(拍位置で固定した並び。WordSense.vowel_transition_at)で当たった、読みの字。
  def vowel_transition_ranges(reading)
    position, pattern = @search.vowel_transition_path
    return [] unless position

    vowels, owners = vowel_owners(reading)
    start = position - 1
    return [] unless vowels[start, pattern.length] == pattern

    [ owner_range(owners, start...(start + pattern.length)) ].compact
  end

  # 音の成分で絞り込んだとき、数えた字。成分ごとに 1 枚の層。
  def sound_ranges(reading)
    SOUND_CHARS.filter_map do |key, chars|
      next unless @search.public_send(key)

      reading.each_char.with_index.filter_map { |char, index| (index...(index + 1)) if chars.include?(char) }
    end
  end

  # 読みのローマ字の片。片の位置は畳んだ読み(KanaFold.to_hiragana)の字の位置なので、畳んで字数が変わる読み
  # (半角カナ・合成濁点)は字へ戻せない。そのときは片を返さない(ハイライトしないだけで、検索は変わらない)。
  def romaji_segments(reading)
    @romaji_segments ||= {}
    @romaji_segments[reading] ||=
      KanaFold.to_hiragana(reading).length == reading.length ? RhythmPattern.segments(reading) : []
  end

  # ローマ字の範囲を、その範囲に掛かる片を生んだ読みの字の範囲にする。
  def reading_range(segments, romaji_range)
    offset = 0
    covered = segments.filter_map do |segment|
      from = offset
      offset += segment.romaji.length
      segment.range if from < romaji_range.end && romaji_range.begin < offset && offset > from
    end
    covered.empty? ? nil : (covered.first.begin...covered.last.end)
  end

  # 読みの母音の並び(VowelPattern と同じ規則でローマ字から母音だけを抜く)と、母音ごとにそれを生んだ読みの字の範囲。
  def vowel_owners(reading)
    owners = romaji_segments(reading).flat_map do |segment|
      segment.romaji.each_char.reject { |char| char.match?(VowelPattern::NON_VOWEL) }.map { |char| [ char, segment.range ] }
    end
    [ owners.map(&:first).join, owners.map(&:last) ]
  end

  # 母音の並びの範囲を、それを生んだ読みの字の範囲にする。
  def owner_range(owners, vowel_range)
    covered = owners[vowel_range]
    covered.blank? ? nil : (covered.first.begin...covered.last.end)
  end

  # 正規表現に当たった範囲。{ surface: { word_id => [Range] }, reading: { word_sense_id => [Range] } }。
  # 一覧に出す語ぶんだけを 1 回で問い合わせる。照合の打ち切り(regexp_time_limit)などで失敗したらハイライトしない。
  def regexp_marks
    return @regexp_marks if defined?(@regexp_marks)

    @regexp_marks = { surface: {}, reading: {} }
    regexp = @search.search_regexp
    return @regexp_marks unless regexp.present? && regexp.error.nil? && @words.any?

    rows = WordSense.joins(:word).where(word_id: @words.map(&:id)).pluck(
      :id, :word_id, :reading, Arel.sql("words.surface"),
      Arel.sql(WordSense.sanitize_sql_array([ REGEXP_MARKED_READING, regexp.for_reading ])),
      Arel.sql(WordSense.sanitize_sql_array([ REGEXP_MARKED_SURFACE, regexp.for_surface ]))
    )
    rows.each do |sense_id, word_id, reading, surface, marked_reading, marked_surface|
      @regexp_marks[:reading][sense_id] = ranges_from_marks(marked_reading, reading)
      @regexp_marks[:surface][word_id] = ranges_from_marks(marked_surface, surface)
    end
    @regexp_marks
  rescue ActiveRecord::StatementInvalid
    @regexp_marks = { surface: {}, reading: {} }
  end

  # 目印を挿んだ文字列から、当たった範囲を取り出す。空の当たり(「x*」や「^」)は囲まない。
  def ranges_from_marks(marked, original)
    plain = +""
    ranges = []
    open_at = nil
    marked.to_s.each_char do |char|
      case char
      when MATCH_OPEN then open_at = plain.length
      when MATCH_CLOSE
        ranges << (open_at...plain.length) if open_at && plain.length > open_at
        open_at = nil
      else plain << char
      end
    end
    plain == original.to_s ? ranges : []
  end

  # 絞り込んだ特徴の付いた語義と、その特徴の行。[[sense, [WordSenseFeature, ...]], ...]。
  def feature_senses(word)
    feature_ids = @search.linguistic_feature_id.map(&:to_i)
    return [] if feature_ids.empty?

    word.word_senses.filter_map do |sense|
      features = sense.word_sense_features.select { |feature| feature_ids.include?(feature.linguistic_feature_id) }
      [ sense, features ] if features.any?
    end
  end

  # 表層形の該当部分は target_start から。位置が表層形とずれていたら(表層形を直したあと。WordSenseFeature の注記)、
  # 最初の出現位置で囲む。
  def feature_surface_ranges(surface, features)
    features.filter_map do |feature|
      start = feature_surface_start(surface, feature)
      start && (start...(start + feature.target.length))
    end
  end

  def feature_surface_start(surface, feature)
    in_place = surface[feature.target_start, feature.target.length] == feature.target
    in_place ? feature.target_start : surface.index(feature.target)
  end

  # 読みの該当部分は位置を持たないので、target_reading の出現を探す。同じ該当部分が繰り返し現れる語
  # (「びしょびしょ…びしょびしょ」)では、表層形で何番目の出現かを数え、読みでも同じ番目の出現を囲む
  # (読みでそこまで現れなければ、最初の出現)。
  def feature_reading_ranges(surface, reading, features)
    features.filter_map do |feature|
      ordinal = occurrences(surface, feature.target).index(feature_surface_start(surface, feature)) || 0
      starts = occurrences(reading, feature.target_reading)
      start = starts[ordinal] || starts.first
      start && (start...(start + feature.target_reading.length))
    end
  end

  # text の中で part が現れる位置(重ならないように前から数える)。
  def occurrences(text, part)
    positions = []
    start = text.index(part)
    while start
      positions << start
      start = text.index(part, start + part.length)
    end
    positions
  end
end
