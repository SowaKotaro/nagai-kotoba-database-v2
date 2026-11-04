# 公開ランキングページ(/rankings)の1枠を表すオブジェクト(DB とキャッシュを読む)。
#
# 各枠は「WordSort のランキング用の並び(WordSort::RANKING_KEYS)」のいずれかに対応する
# (並びのうち、順位表として出さないものはこのカタログに載せない)。
# ページ上では値の違う上位 TOP_LIMIT 組を 1〜TOP_LIMIT 位として見せ、「もっと見る」は同じキーで並べた
# 単語一覧(words#index?sort=...)へ渡す。順位付けの規則を1か所に閉じるため、
# 指標式・下限・表示書式・同じ値の組の作り方はすべてこのカタログが持つ。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class WordRanking
  TOP_LIMIT = 10
  # 同じ値の組で、代表の下に畳む語の上限。超えたぶんは語数だけを示し、続きは同じ並びの一覧に任せる
  # (下の順位の組は「長音符 1 本」のように、収録が進むと数百語になりうる)。
  FOLD_LIMIT = 50
  # 比率(format: :decimal)を表示する小数の桁数。同じ値の組も、この桁に丸めた値で作る。
  DECIMAL_PLACES = 2
  # 集計結果のキャッシュ。統計ページ(SiteStatistics)と同じく1日で作り直す。
  CACHE_KEY = "word_rankings/v2"
  CACHE_TTL = 1.day

  # key           : WordSort のキー(= もっと見るの sort パラメータ・i18n のキー)
  # icon          : 見出しに添えるインライン SVG 名
  # minimum       : この値未満の語はランキングに載せない(0本の長音符などを並べない)
  # format        : 値の表示書式(:integer / :decimal)
  # 該当語が TOP_LIMIT 件以下の枠はページに出さない(board)。
  DEFINITIONS = [
    { key: "length_desc",           icon: "ruler",      minimum: 1 },
    { key: "mora_desc",             icon: "metronome",  minimum: 1 },
    { key: "surface_length_desc",   icon: "text_aa",    minimum: 1 },
    # 比率なので下限を設けない(1未満 = 読みより字面が長い語も母集団に含める)。
    { key: "reading_density_desc",  icon: "scales",     minimum: 0, format: :decimal },
    { key: "small_kana_desc",       icon: "quote_ab",   minimum: 1 },
    { key: "chouon_desc",           icon: "music_notes", minimum: 1 },
    { key: "dakuten_desc",          icon: "quotes",     minimum: 1 },
    { key: "ring_crossing_desc",    icon: "pentagram", minimum: 1 },
    # 少ない順は 0 回の語こそが主役なので下限を設けない(0 回の語は 1 組にまとまり、読みが長い語が代表になる)。
    { key: "ring_crossing_asc",     icon: "pentagram", minimum: 0 },
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
  # 値の小さい順に並べる枠か。キーの末尾(_asc / _desc)が WordSort の並びの向きを表す。
  def ascending? = key.end_with?("_asc")

  # ランキングページに出す順位表(groups をキャッシュしたもの)。該当語が TOP_LIMIT 件以下の枠は
  # 順位表として成立しないので空を返す(2026-09-17 時点で「語義が多い順」は該当 10 語で全員が載っていた。
  # Issue 100)。収録が進めば自然に出てくるので、枠そのものは消さない。
  def board
    Rails.cache.fetch("#{CACHE_KEY}/#{key}", expires_in: CACHE_TTL) do
      ranked_words.count > TOP_LIMIT ? groups : []
    end
  end

  # 値の違う上位 TOP_LIMIT 組。順位は組ごとに 1 から振る(同じ値の語数で次の順位を飛ばさない。
  # 飛ばすと、同じ値の語が増えたときに 1 位の組しか載らない順位表になる。2026-11-04 オーナー判断)。
  #   [{ rank:, value:, count:, offset:, representative: { id:, surface:, readings: }, others: [{ id:, surface: }] }]
  # 組は読みがいちばん長い語を代表に立て、残りを others に畳む(FOLD_LIMIT 語まで。count は組の語数)。
  # offset は上の組の語数の合計で、同じ並びの単語一覧でこの組が始まる位置(0 始まり)になる。
  def groups
    counts = value_counts
    values = ascending? ? counts.keys.sort : counts.keys.sort.reverse
    values.first(TOP_LIMIT).each_with_index.map do |value, index|
      members = ranked_words.where(metric_column => stored_values(value))
      representative, *others = members.reorder(max_reading_length: :desc, id: :asc)
                                       .limit(1 + FOLD_LIMIT).includes(:word_senses).to_a
      { rank: index + 1, value: value, count: counts[value], offset: values.first(index).sum { |above| counts[above] },
        representative: { id: representative.id, surface: representative.surface,
                          readings: representative.word_senses.map(&:reading) },
        others: others.map { |word| { id: word.id, surface: word.surface } } }
    end
  end

  private

  # 指標が入っている words のカラム(WordSort::RANKING_METRICS のホワイトリスト)。
  def metric_column
    WordSort::RANKING_METRICS.fetch(key)
  end

  # 下限を満たす公開語を、単語一覧と同じ並びで。指標は words のカラムなので、下限は素の WHERE で掛かり、
  # 並べ替えとあわせて「指標 + id」の複合インデックスだけで解ける。
  # 語義が1つも無い語は指標が NULL になり、この範囲条件で自然に落ちる。
  def ranked_words
    Word.annotated
        .where(metric_column => minimum..)
        .order(WordSort.new(key).order_clause)
  end

  # 表示する値ごとの語数 { 値 => 語数 }。比率は表示の桁に丸めた値でまとめる(表示が同じなら 1 組)。
  def value_counts
    ranked_words.unscope(:order).group(metric_column).count
                .each_with_object(Hash.new(0)) { |(value, count), counts| counts[normalize(value)] += count }
  end

  # 1字あたりの読みの長さ(reading_density)だけ DECIMAL で返るため、表示と同じ桁に丸めて数値へ寄せる
  # (BigDecimal#round の四捨五入。stored_values の幅と同じ規則)。
  def normalize(value)
    decimal? ? value.round(DECIMAL_PLACES).to_f : value.to_i
  end

  # 丸めると value になる、カラムに入りうる値。比率は表示が同じなら 1 組にするので、四捨五入の幅で引く
  # (例: 37/14 = 2.6429 と 29/11 = 2.6364 はどちらも 2.64)。
  def stored_values(value)
    return value unless decimal?

    half_step = BigDecimal("0.5") / (10**DECIMAL_PLACES)
    (BigDecimal(value.to_s) - half_step)...(BigDecimal(value.to_s) + half_step)
  end
end
