# 語義(WordSense)の検索・絞り込みを組み立てるクエリオブジェクト(Issue 9)。
# 生成カラム(reading_length / first_char)や last_char(Ruby 側で計算)のインデックスを
# 活かした条件を、指定されたものだけ AND で積み重ねて Relation を返す。
class WordSenseSearch
  def initialize(params)
    @params = params || {}
  end

  # 絞り込み済みで並び順を付けた Relation を返す(空条件なら公開全件)。
  # 公開検索なので注釈済み(published)の語義のみを対象にする。
  def results
    relation = WordSense.published
    relation = relation.keyword(q) if q.present?
    # 不正なパターンは条件から外す(SQL エラーにせず、他の条件だけで検索する)。
    relation = relation.regexp_matching(search_regexp) if search_regexp.present? && regexp_error.nil?
    relation = relation.reading_length_at_least(reading_length_min) if reading_length_min
    relation = relation.reading_length_at_most(reading_length_max) if reading_length_max
    relation = relation.reading_length_is(reading_length) if reading_length
    relation = relation.mora_count_is(mora_count) if mora_count
    relation = relation.first_char_is(first_char) if first_char.present?
    relation = relation.last_char_is(last_char) if last_char.present?
    if char_type_pattern.present?
      relation = relation.char_type_pattern_matching(char_type_pattern,
                                                     partial: char_type_partial?,
                                                     case_sensitive: char_type_case_sensitive?)
    end
    relation = relation.rhythm_containing(rhythm_pattern) if rhythm_pattern.present?
    relation = relation.vowel_containing(vowel_pattern_query) if vowel_pattern_query.present?
    relation = relation.with_part_of_speech(part_of_speech_id) if part_of_speech_id.present?
    relation = relation.with_entity_type(entity_type_id) if entity_type_id.present?
    relation = relation.with_word_origin(word_origin_id) if word_origin_id.present?
    relation = relation.with_linguistic_feature(linguistic_feature_id) if linguistic_feature_id.present?
    relation = relation.with_genre_ids(genre_filter_ids) if genre_filter_ids
    relation.order(:reading, :id)
  end

  # --- フォーム再表示用に、受け取った値をそのまま返すアクセサ ---
  def q = @params[:q].to_s.strip
  def regexp = search_regexp.source
  # 正規表現条件の値オブジェクト。フォームの入力値・エラー判定・実際に投げるパターンを持つ。
  def search_regexp = @search_regexp ||= SearchRegexp.new(@params[:regexp])
  # 検索前に分かる正規表現のエラー(:syntax / :too_long)。無ければ nil。
  def regexp_error = search_regexp.error
  def reading_length_min = positive_integer(:reading_length_min)
  def reading_length_max = positive_integer(:reading_length_max)
  def reading_length = positive_integer(:reading_length)
  def mora_count = positive_integer(:mora_count)
  # 大文字小文字を区別しないときは「a」と「A」が同義になるため「A」に畳んで返す。
  # 検索結果は変わらないが、フォームの表示と引き継ぐ URL が一意になる。
  def char_type_pattern
    raw = @params[:char_type_pattern].to_s.strip
    char_type_case_sensitive? ? raw : raw.tr(CharTypePattern::LOWER, CharTypePattern::UPPER)
  end
  # 文字種検索の一致方法。既定は完全一致で、トグル(char_type_partial)を入れたときだけ部分一致。
  def char_type_partial? = boolean(:char_type_partial)
  # 文字種検索の大文字小文字。既定は区別する。トグル(char_type_ignore_case)で区別しない。
  def char_type_case_sensitive? = !boolean(:char_type_ignore_case)
  def rhythm_pattern = @params[:rhythm_pattern].to_s.strip
  # 母音パターン検索のフォーム入力(押韻したい読みのカナ)。表示はこの生入力のまま返す。
  def vowel_reading = @params[:vowel_reading].to_s.strip
  # 複数選択(OR)の条件。単一値でも配列でも受ける(詳細検索は配列、ファセットリンクは単一)。
  def genre_id = value_list(:genre_id)
  def first_char = value_list(:first_char)
  def last_char = value_list(:last_char)
  def part_of_speech_id = value_list(:part_of_speech_id)
  def entity_type_id = value_list(:entity_type_id)
  def word_origin_id = value_list(:word_origin_id)
  def linguistic_feature_id = value_list(:linguistic_feature_id)

  # 指定された条件だけを、空を除いたハッシュで返す。
  # 検索実行時に単語一覧へ条件を引き継ぐリダイレクトや、絞り込み有無の判定に使う。
  def to_query_params
    {
      q: q.presence,
      regexp: regexp.presence,
      reading_length_min: reading_length_min,
      reading_length_max: reading_length_max,
      reading_length: reading_length,
      mora_count: mora_count,
      first_char: first_char.presence,
      last_char: last_char.presence,
      genre_id: genre_id.presence,
      part_of_speech_id: part_of_speech_id.presence,
      entity_type_id: entity_type_id.presence,
      linguistic_feature_id: linguistic_feature_id.presence,
      word_origin_id: word_origin_id.presence,
      rhythm_pattern: rhythm_pattern.presence,
      vowel_reading: vowel_reading.presence,
      char_type_pattern: char_type_pattern.presence,
      # トグルは既定と異なる(=有効な)ときだけ引き継ぐ。文字種パターンがある場合に限る。
      char_type_partial: ("1" if char_type_pattern.present? && char_type_partial?),
      char_type_ignore_case: ("1" if char_type_pattern.present? && !char_type_case_sensitive?)
    }.compact
  end

  # 何かひとつでも絞り込み条件が指定されているか。
  def conditions? = to_query_params.any?

  # インデックス(検索エンジン登録)を許可するファセット。単一値のカテゴリ的条件のみ(Issue 17)。
  # 読みの長さ・モーラ・キーワード等は組合せ爆発・重複コンテンツになるため含めない。
  INDEXABLE_FACET_KEYS = %i[genre_id part_of_speech_id entity_type_id word_origin_id first_char].freeze

  # 条件がちょうど1つで、それが単一値のインデックス許可ファセットなら [key, value] を返す。
  # それ以外(複数条件・キーワード・複数選択・非対象の軸)は nil。
  def indexable_facet
    params = to_query_params
    return nil unless params.size == 1

    key, value = params.first
    return nil unless INDEXABLE_FACET_KEYS.include?(key)

    values = Array(value)
    return nil unless values.size == 1

    [ key, values.first ]
  end

  # 選択したジャンルのうち、選択済みの下位を持つ上位を除いた「実効の節点」。
  # 例: 大「文学」と中「日本文学」を両方選んだら、より具体的な「日本文学」を採用する。
  # 条件チップの表示(SearchesHelper)でも使うため公開している。
  def effective_genres
    return @effective_genres if defined?(@effective_genres)

    selected = Genre.where(id: genre_id).to_a
    ancestor_ids = selected.filter_map(&:parent_id)
    ancestor_ids |= Genre.where(id: ancestor_ids).filter_map(&:parent_id)
    @effective_genres = selected.reject { |genre| ancestor_ids.include?(genre.id) }
  end

  # 母音パターン検索のクエリ文字列。フォームには読みをカナで入力してもらい、
  # ヘボン式ローマ字→母音のみ(aiueo)へ変換して vowel_pattern と部分一致させる。
  # (例: 「トウキョウタワー」→「ououaa」)。母音字を直接入れた場合もそのまま通る。
  def vowel_pattern_query
    return @vowel_pattern_query if defined?(@vowel_pattern_query)

    @vowel_pattern_query = VowelPattern.call(RhythmPattern.call(vowel_reading))
  end

  private

  # 正の整数のときだけ値を返す(0・空・非数値は無視)。
  def positive_integer(key)
    value = @params[key].to_i
    value if value.positive?
  end

  # チェックボックス由来の真偽値("1"/"true" などを true に)。
  def boolean(key)
    ActiveModel::Type::Boolean.new.cast(@params[key])
  end

  # 単一値/配列いずれの入力も、空を除いた配列に正規化する。
  def value_list(key)
    Array(@params[key]).map { |v| v.to_s.strip }.reject(&:blank?)
  end

  # 選択したジャンル(大/中/小いずれか・複数可)を、末端(小分類)の id 群に展開する(OR)。
  # genre_id は小分類しか指さないため、上位を選んだら配下の小分類すべてで絞り込む。
  def genre_filter_ids
    return @genre_filter_ids if defined?(@genre_filter_ids)

    @genre_filter_ids = effective_genres.presence &&
                        effective_genres.flat_map { |genre| small_descendant_ids(genre) }.uniq
  end

  def small_descendant_ids(genre)
    case genre.level
    when "small"  then [ genre.id ]
    when "medium" then Genre.where(parent_id: genre.id).pluck(:id)
    when "large"
      medium_ids = Genre.where(parent_id: genre.id).pluck(:id)
      medium_ids.empty? ? [] : Genre.where(parent_id: medium_ids).pluck(:id)
    end
  end
end
