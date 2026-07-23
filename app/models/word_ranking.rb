# 公開ランキングページ(/rankings)の1枠を表す値オブジェクト。
#
# 各枠は「WordSort のランキング用の並び(WordSort::RANKING_KEYS)」のいずれかに対応する
# (並びのうち、順位表として出さないものはこのカタログに載せない)。
# ページ上では上位 TOP_LIMIT 件だけを見せ、「もっと見る」は同じキーで並べた
# 単語一覧(words#index?sort=...)へ渡す。順位付けの規則を1か所に閉じるため、
# 指標式・下限・表示書式はすべてこのカタログが持つ。
class WordRanking
  # 各ランキングで見せる件数。
  TOP_LIMIT = 10
  # 集計結果のキャッシュ。統計ページ(SiteStatistics)と同じく1日で作り直す。
  CACHE_KEY = "word_rankings/v1"
  CACHE_TTL = 1.day

  # key           : WordSort のキー(= もっと見るの sort パラメータ・i18n のキー)
  # icon          : 見出しに添えるインライン SVG 名
  # minimum       : この値未満の語はランキングに載せない(0本の長音符などを並べない)
  # format        : 値の表示書式(:integer / :decimal)
  # 該当語が1つも無い枠(アノテーション待ちの特徴など)はページ側で丸ごと省く。
  DEFINITIONS = [
    { key: "length_desc",           icon: "ruler",      minimum: 1 },
    { key: "mora_desc",             icon: "metronome",  minimum: 1 },
    { key: "surface_length_desc",   icon: "text_aa",    minimum: 1 },
    # 比率なので下限を設けない(1未満 = 読みより字面が長い語も母集団に含める)。
    { key: "reading_density_desc",  icon: "scales",     minimum: 0, format: :decimal },
    { key: "small_kana_desc",       icon: "quote_ab",   minimum: 1 },
    { key: "chouon_desc",           icon: "music_notes", minimum: 1 },
    { key: "dakuten_desc",          icon: "quotes",     minimum: 1 },
    { key: "ring_crossing_desc",    icon: "ring_crossings", minimum: 1 },
    # 少ない順は 0 回の語こそが主役なので下限を設けない(同値の並びは WordSort が読みの長い順で解く)。
    { key: "ring_crossing_asc",     icon: "ring_crossings", minimum: 0 },
    { key: "sense_count_desc",      icon: "book_open",  minimum: 2 },
    # 別表記の多さ(variant_count_desc)は順位表としては出さない(オーナー判断)。
    # 一覧の並び替え(WordSort::SELECTABLE_KEYS)としては残す。
    { key: "feature_count_desc",    icon: "pen_nib",    minimum: 1 }
  ].freeze

  def self.all
    DEFINITIONS.map { |definition| new(**definition) }
  end

  attr_reader :key, :icon, :minimum, :format

  def initialize(key:, icon:, minimum: 1, format: :integer)
    @key = key
    @icon = icon
    @minimum = minimum
    @format = format
  end

  def title = I18n.t("rankings.boards.#{key}.title")
  # 値に添える単位(「28字」の「字」)。
  def unit = I18n.t("rankings.boards.#{key}.unit")
  def decimal? = format == :decimal

  # 上位 limit 件 [{ rank:, id:, surface:, readings:, value: }]。
  # 値が同じ語は同順位にし、その分だけ次の順位を飛ばす(競技順位)。
  def top(limit: TOP_LIMIT)
    Rails.cache.fetch("#{CACHE_KEY}/#{key}/#{limit}", expires_in: CACHE_TTL) { build_top(limit) }
  end

  private

  def build_top(limit)
    rows = words(limit).map do |word|
      { id: word.id, surface: word.surface,
        readings: word.word_senses.map(&:reading), value: normalize(word.ranking_metric) }
    end
    with_ranks(rows)
  end

  # 指標を ranking_metric として持ち帰った公開語。SQL 片は WordSort の定数だけを使う。
  # 下限の絞り込みは、同じ式を二度書かずに済むよう別名への HAVING で掛ける
  # (MySQL は GROUP BY なしの HAVING と、そこでの別名参照を許す)。
  def words(limit)
    Word.annotated
        .select(WordSort::RANKING_SELECTS.fetch(key))
        .having("ranking_metric >= ?", minimum)
        .order(WordSort.new(key).order_clause)
        .limit(limit)
        .includes(:word_senses)
  end

  # MySQL からは指標が BigDecimal(除算)や文字列で返るため、表示前に数値へ寄せる。
  def normalize(value)
    decimal? ? value.to_f.round(2) : value.to_i
  end

  def with_ranks(rows)
    rank = 0
    previous_value = nil
    rows.each_with_index.map do |row, index|
      rank = index + 1 unless row[:value] == previous_value
      previous_value = row[:value]
      row.merge(rank: rank)
    end
  end
end
