# 公開統計ページ(/stats)の集計一式(docs/stats.md)。
# 派生カラム(reading_length / mora_count / first_char / last_char / char_type_pattern /
# vowel_pattern / rhythm_pattern)への GROUP BY を中心に、想定1万レコード規模を
# オンライン集計する(Issue 34 Phase 1)。結果は Rails.cache に1日置く(毎日再集計)。
#
# すべての集計は公開対象(注釈済みの語・その語義)だけを数える。
# ジャンル・語種・エンティティ・特徴はアノテーション依存のため、
# ビュー側で「集計対象は◯語義」を明示する(covered 系の値を使う)。
class SiteStatistics
  # 集計の構造を変えたらキャッシュに残る旧オブジェクトを踏まないようバージョンを上げる。
  CACHE_KEY = "site_statistics/v2"
  CACHE_TTL = 1.day

  # 語義に複数の語種が付いた語(語種の多対多)を束ねる表示名。
  MIXED_ORIGIN = "混種語"
  # 語種ワッフル(10×10=100マス)で個別に見せる語種の数。残りは「その他」に束ねる。
  ORIGIN_CATEGORY_LIMIT = 4
  WAFFLE_CELLS = 100
  OTHER_LABEL = "その他"
  # 母音スペクトルの拍位置は、全語義の1割を下回る位置で打ち切る(端の希薄なノイズを見せない)。
  SPECTRUM_SUPPORT_RATIO = 0.1
  SPECTRUM_MAX_POSITIONS = 24
  VOWELS = %w[a i u e o].freeze

  def self.fetch
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new }
  end

  attr_reader :computed_at,
              :scale, :reading_length, :letters, :growth,
              :first_char_counts, :last_char_counts,
              :sound_matrix, :reading_length_distribution, :mora_distribution,
              :timeline, :genre_map, :origins, :entity_types,
              :vowel_spectrum, :head_consonants, :feature_ranking

  # キャッシュにはこのオブジェクトごと入れるため、初期化時にすべて計算し切る。
  def initialize
    @computed_at = Time.current
    @word_count = Word.annotated.count
    @sense_count = WordSense.published.count
    @reading_length_counts = WordSense.published.group(:reading_length).count
    # 50音表ヒートマップで引けるよう、キーはカタカナへ正規化して畳んでおく。
    @first_char_counts = normalized_kana_counts(WordSense.published.group(:first_char).count)
    @last_char_counts = normalized_kana_counts(WordSense.published.group(:last_char).count)

    @scale = build_scale
    @reading_length = build_reading_length
    @letters = build_letters
    @growth = build_growth
    @sound_matrix = build_sound_matrix
    @reading_length_distribution = fill_distribution(@reading_length_counts)
    @mora_distribution = fill_distribution(WordSense.published.group(:mora_count).count)
    @timeline = build_timeline
    @genre_map = build_genre_map
    @origins = build_origins
    @entity_types = build_entity_types
    @vowel_spectrum = build_vowel_spectrum
    @head_consonants = build_head_consonants
    @feature_ranking = build_feature_ranking
  end

  def word_count = @word_count
  def sense_count = @sense_count

  private

  # ==== 数字の壁 ====================================================================

  # 規模: 収録語・語義・別表記・同音異義の組・のべ読み文字。
  def build_scale
    {
      words: @word_count,
      senses: @sense_count,
      variants: WordSenseVariant.joins(word_sense: :word).merge(Word.annotated).count,
      homophone_groups: WordSense.published.group(:reading).having("COUNT(*) > 1").count.length,
      total_reading_chars: WordSense.published.sum(:reading_length)
    }
  end

  # 読みの長さ: 平均・中央値・最頻・最長・平均モーラ。
  def build_reading_length
    {
      average: WordSense.published.average(:reading_length)&.to_f&.round(1),
      median: median_from_counts(@reading_length_counts),
      mode: mode_from_counts(@reading_length_counts),
      max: @reading_length_counts.keys.max,
      average_mora: WordSense.published.average(:mora_count)&.to_f&.round(1)
    }
  end

  # 文字と音: 頭文字/末尾文字のカバレッジ(46字中)・カタカナのみ%・漢字を含む%・「ー」を含む%。
  def build_letters
    {
      first_char_kinds: base_kana_kinds(@first_char_counts.keys),
      last_char_kinds: base_kana_kinds(@last_char_counts.keys),
      kana_total: KanaRow::BASE_46.size,
      katakana_only_pct: percent(Word.annotated.where("char_type_pattern REGEXP ?", "^ア+$").count, @word_count),
      with_kanji_pct: percent(Word.annotated.where("char_type_pattern LIKE ?", "%漢%").count, @word_count),
      with_chouon_pct: percent(WordSense.published.where("reading LIKE ?", "%ー%").count, @sense_count)
    }
  end

  # 分類と歩み: 今月の新収録・使用中ジャンル数・使用中特徴数・1日あたり平均・開帳からの日数。
  def build_growth
    first_day = Word.annotated.minimum(:created_at)&.to_date
    days_open = first_day ? (Date.current - first_day).to_i + 1 : 0
    {
      this_month: Word.annotated.where(created_at: Time.current.all_month).count,
      genre_count: WordSense.published.where.not(genre_id: nil).distinct.count(:genre_id),
      feature_count: WordSenseFeature.joins(word_sense: :word).merge(Word.annotated)
                                     .distinct.count(:linguistic_feature_id),
      per_day: days_open.positive? ? @word_count.fdiv(days_open).round(1) : 0,
      days_open: days_open
    }
  end

  # ==== §2 音のはじまりとおわり(行×行マトリクス) ==================================

  # { cells: { [頭文字の行, 末尾文字の行] => 語義数 }, max_pair:, max_count: }
  # 行に写像できない文字(記号など)は数えない。
  def build_sound_matrix
    cells = Hash.new(0)
    WordSense.published.group(:first_char, :last_char).count.each do |(first, last), count|
      first_row = KanaRow.row(first)
      last_row = KanaRow.row(last)
      cells[[ first_row, last_row ]] += count if first_row && last_row
    end
    max_pair, max_count = cells.max_by { |_, count| count }
    { cells: cells, max_pair: max_pair, max_count: max_count.to_i }
  end

  # ==== §3 読みの長さ分布(文字数・モーラ) ==========================================

  # 分布の横軸の上限。まれな超長語が散らばると横軸が間延びするため、
  # この値以上は「30+」の1本にまとめる。
  DISTRIBUTION_OVERFLOW_MIN = 30

  # 最小〜上限の間を 0 件も含めて埋めた [{ value:, count: }] を返す(棒の欠番を作らない)。
  # DISTRIBUTION_OVERFLOW_MIN 以上は overflow: true を立てた1本にまとめる。
  def fill_distribution(counts)
    values = counts.keys.compact
    return [] if values.empty?

    bins = (values.min..[ values.max, DISTRIBUTION_OVERFLOW_MIN - 1 ].min).map do |value|
      { value: value, count: counts[value].to_i }
    end
    overflow_count = values.select { |value| value >= DISTRIBUTION_OVERFLOW_MIN }.sum { |value| counts[value].to_i }
    bins << { value: DISTRIBUTION_OVERFLOW_MIN, count: overflow_count, overflow: true } if overflow_count.positive?
    bins
  end

  # ==== §4 収録の推移(週次) ========================================================

  # 開帳の週から今週までを 0 件の週も含めて並べた [{ start_on:, count:, cumulative: }]。
  def build_timeline
    weekly = Word.annotated.pluck(:created_at).map { |time| time.to_date.beginning_of_week }.tally
    return [] if weekly.empty?

    cumulative = 0
    weeks = []
    week = weekly.keys.min
    last_week = Date.current.beginning_of_week
    while week <= last_week
      cumulative += weekly[week].to_i
      weeks << { start_on: week, count: weekly[week].to_i, cumulative: cumulative }
      week += 7
    end
    weeks
  end

  # ==== ジャンル別の語義数(サンバースト用・大→中→小の3階層) ======================

  # { covered:, groups: [{ id:, name:, count:, children: [{ …, children: [{ id:, name:, count: }] }] }] }
  def build_genre_map
    genre_counts = WordSense.published.where.not(genre_id: nil).group(:genre_id).count
    genres = Genre.all.index_by(&:id)
    groups = {}
    genre_counts.each do |small_id, count|
      small = genres[small_id]
      medium = small && genres[small.parent_id]
      large = medium && genres[medium.parent_id]
      next unless large

      large_node = groups[large.id] ||= { count: 0, children: {} }
      medium_node = large_node[:children][medium.id] ||= { count: 0, children: {} }
      large_node[:count] += count
      medium_node[:count] += count
      medium_node[:children][small_id] = count
    end

    {
      covered: genre_counts.values.sum,
      groups: groups.map do |large_id, large_node|
        {
          id: large_id, name: genres[large_id].name, count: large_node[:count],
          children: large_node[:children].map do |medium_id, medium_node|
            {
              id: medium_id, name: genres[medium_id].name, count: medium_node[:count],
              children: medium_node[:children].map { |small_id, count| { id: small_id, name: genres[small_id].name, count: count } }
                                              .sort_by { |small| -small[:count] }
            }
          end.sort_by { |medium| -medium[:count] }
        }
      end.sort_by { |large| -large[:count] }
    }
  end

  # ==== §6 ことばの出どころ(語種・エンティティ型) ==================================

  # 語種構成のワッフル(100マス)。複数語種の語義は「混種語」に束ね、
  # 上位4語種 + その他に整理して各カテゴリへマスを配分する。
  def build_origins
    pairs = WordSenseOrigin.joins(word_sense: :word).merge(Word.annotated)
                           .pluck(:word_sense_id, :word_origin_id)
    names = WordOrigin.pluck(:id, :name).to_h
    counts = pairs.group_by(&:first).values.map do |rows|
      origin_ids = rows.map(&:last).uniq
      origin_ids.size > 1 ? MIXED_ORIGIN : names[origin_ids.first]
    end.tally

    sorted = counts.sort_by { |_, count| -count }
    categories = sorted.first(ORIGIN_CATEGORY_LIMIT).map { |name, count| { name: name, count: count } }
    rest = sorted.drop(ORIGIN_CATEGORY_LIMIT).sum { |_, count| count }
    categories << { name: OTHER_LABEL, count: rest } if rest.positive?

    { covered: counts.values.sum, categories: allocate_waffle_cells(categories) }
  end

  # 最大剰余法で 100 マスを配分する(合計をぴったり 100 に保つ)。
  def allocate_waffle_cells(categories)
    total = categories.sum { |category| category[:count] }
    return categories if total.zero?

    with_share = categories.map do |category|
      exact = category[:count] * WAFFLE_CELLS.to_f / total
      category.merge(cells: exact.floor, remainder: exact - exact.floor)
    end
    (WAFFLE_CELLS - with_share.sum { |category| category[:cells] }).times do |i|
      with_share.sort_by { |category| -category[:remainder] }[i][:cells] += 1
    end
    with_share.map { |category| category.except(:remainder) }
  end

  # エンティティ型のタグクラウド用 [{ id:, name:, count: }](多い順)。
  def build_entity_types
    counts = WordSense.published.where.not(entity_type_id: nil).group(:entity_type_id).count
    names = EntityType.where(id: counts.keys).pluck(:id, :name).to_h
    counts.map { |id, count| { id: id, name: names[id], count: count } }
          .sort_by { |entity| -entity[:count] }
  end

  # ==== §7 音の内訳(母音スペクトル・頭子音) ========================================

  # 語頭からの拍位置ごとの母音構成 [{ position:, total:, counts: { "a" => n, ... } }]。
  # その位置まで読みが続く語義が全体の1割を切ったら打ち切る。
  def build_vowel_spectrum
    patterns = WordSense.published.where.not(vowel_pattern: [ nil, "" ]).pluck(:vowel_pattern)
    return { total: 0, positions: [] } if patterns.empty?

    support_floor = [ (patterns.size * SPECTRUM_SUPPORT_RATIO).ceil, 1 ].max
    limit = [ patterns.map(&:length).max, SPECTRUM_MAX_POSITIONS ].min
    positions = []
    (0...limit).each do |index|
      vowels = patterns.filter_map { |pattern| pattern[index] }
      # 読みがその位置まで続く語義が減ってきたら打ち切る(先頭の位置は必ず含める)。
      break if vowels.size < support_floor && index.positive?

      counts = vowels.tally.slice(*VOWELS)
      positions << { position: index + 1, total: counts.values.sum, counts: counts }
    end
    { total: patterns.size, positions: positions }
  end

  # 読み第1拍の子音ランキング [{ consonant: "k"|nil, chars: [観測された頭文字], count: }]。
  # consonant はヘボン式の頭子音(rhythm_pattern の文法)、nil は母音始まり。
  # 拗音(シャ等)は頭文字1字に畳まれる(シャ→シ)ため、子音は頭文字から導出する。
  def build_head_consonants
    groups = Hash.new { |hash, key| hash[key] = { count: 0, chars: [] } }
    @first_char_counts.each do |char, count|
      next unless KanaRow.row(char)

      consonant = RhythmPattern.call(char)[/\A[^aeiou]+/]
      groups[consonant][:count] += count
      groups[consonant][:chars] << char
    end
    groups.map { |consonant, group| { consonant: consonant, chars: group[:chars].sort, count: group[:count] } }
          .sort_by { |group| -group[:count] }
  end

  # ==== §8 ことばの見どころ(言語学的特徴) ==========================================

  # 特徴の件数ランキングと実例(該当部分に朱下線を引くための surface / target / target_start)。
  def build_feature_ranking
    counts = WordSenseFeature.joins(word_sense: :word).merge(Word.annotated)
                             .group(:linguistic_feature_id).count
    names = LinguisticFeature.where(id: counts.keys).pluck(:id, :name).to_h
    rows = counts.map do |feature_id, count|
      { id: feature_id, name: names[feature_id], count: count, example: feature_example(feature_id) }
    end
    { total: counts.values.sum, rows: rows.sort_by { |row| -row[:count] } }
  end

  # 特徴の実例をひとつ選ぶ(読みが最長の語 = 見本として一番「らしい」語)。
  def feature_example(feature_id)
    feature = WordSenseFeature.where(linguistic_feature_id: feature_id)
                              .joins(word_sense: :word).merge(Word.annotated)
                              .includes(word_sense: :word)
                              .order("word_senses.reading_length DESC", :id).first
    return nil unless feature

    { surface: feature.word_sense.word.surface, target: feature.target, target_start: feature.target_start }
  end

  # ==== 共通 ========================================================================

  # 観測された文字を基本46字(KanaRow::BASE_46)へ畳んだときの種類数(カバレッジの分子)。
  def base_kana_kinds(chars)
    chars.filter_map { |char| KanaRow.base(char) }.uniq.size
  end

  # GROUP BY の結果キーをカタカナへ正規化して畳む(ひらがな読みの混在対策)。
  # DB の照合(as_ci)はひらがな⇔カタカナを同一視するが、返るキーは格納値のままのため。
  def normalized_kana_counts(counts)
    counts.each_with_object(Hash.new(0)) do |(char, count), folded|
      key = char.to_s.unicode_normalize(:nfkc).tr("ぁ-ゖ", "ァ-ヶ")
      folded[key] += count
    end
  end

  def percent(part, total)
    return 0.0 if total.zero?

    (part * 100.0 / total).round(1)
  end

  # { 値 => 件数 } から中央値を求める(偶数件は中央2値の平均)。
  def median_from_counts(counts)
    total = counts.values.sum
    return nil if total.zero?

    sorted = counts.sort_by(&:first)
    lower = value_at_position(sorted, (total + 1) / 2)
    upper = value_at_position(sorted, (total + 2) / 2)
    lower == upper ? lower : (lower + upper) / 2.0
  end

  def value_at_position(sorted_counts, position)
    passed = 0
    sorted_counts.each do |value, count|
      passed += count
      return value if passed >= position
    end
  end

  # { 値 => 件数 } の最頻値(同数なら小さい値)。
  def mode_from_counts(counts)
    counts.min_by { |value, count| [ -count, value ] }&.first
  end
end
