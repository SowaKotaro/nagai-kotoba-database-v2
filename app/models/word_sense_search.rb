# 語義(WordSense)の検索・絞り込みを組み立てるクエリオブジェクト(Issue 9)。
# 生成カラム(reading_length / first_char / last_char)やインデックスを活かした
# 条件を、指定されたものだけ AND で積み重ねて Relation を返す。
class WordSenseSearch
  def initialize(params)
    @params = params || {}
  end

  # 絞り込み済みで並び順を付けた Relation を返す(空条件なら公開全件)。
  # 公開検索なので注釈済み(published)の語義のみを対象にする。
  def results
    relation = WordSense.published
    relation = relation.keyword(q) if q.present?
    relation = relation.reading_length_at_least(reading_length_min) if reading_length_min
    relation = relation.reading_length_at_most(reading_length_max) if reading_length_max
    relation = relation.reading_length_is(reading_length) if reading_length
    relation = relation.mora_count_is(mora_count) if mora_count
    relation = relation.first_char_is(first_char) if first_char.present?
    relation = relation.last_char_is(last_char) if last_char.present?
    relation = relation.char_type_pattern_is(char_type_pattern) if char_type_pattern.present?
    relation = relation.rhythm_containing(rhythm_pattern) if rhythm_pattern.present?
    relation = relation.with_part_of_speech(part_of_speech_id) if part_of_speech_id.present?
    relation = relation.with_entity_type(entity_type_id) if entity_type_id.present?
    relation = relation.with_word_origin(word_origin_id) if word_origin_id.present?
    relation = relation.with_linguistic_feature(linguistic_feature_id) if linguistic_feature_id.present?
    relation = relation.with_genre_ids(genre_filter_ids) if genre_filter_ids
    relation.order(:reading, :id)
  end

  # --- フォーム再表示用に、受け取った値をそのまま返すアクセサ ---
  def q = @params[:q].to_s.strip
  def reading_length_min = positive_integer(:reading_length_min)
  def reading_length_max = positive_integer(:reading_length_max)
  def reading_length = positive_integer(:reading_length)
  def mora_count = positive_integer(:mora_count)
  def char_type_pattern = @params[:char_type_pattern].to_s.strip
  def rhythm_pattern = @params[:rhythm_pattern].to_s.strip
  def genre_id = @params[:genre_id].presence
  def word_origin_id = @params[:word_origin_id].presence
  # 複数選択(OR)の条件。単一値でも配列でも受ける(詳細検索は配列、ファセットリンクは単一)。
  def first_char = value_list(:first_char)
  def last_char = value_list(:last_char)
  def part_of_speech_id = value_list(:part_of_speech_id)
  def entity_type_id = value_list(:entity_type_id)
  def linguistic_feature_id = value_list(:linguistic_feature_id)

  private

  # 正の整数のときだけ値を返す(0・空・非数値は無視)。
  def positive_integer(key)
    value = @params[key].to_i
    value if value.positive?
  end

  # 単一値/配列いずれの入力も、空を除いた配列に正規化する。
  def value_list(key)
    Array(@params[key]).map { |v| v.to_s.strip }.reject(&:blank?)
  end

  # 選択したジャンル(大/中/小いずれか)を、末端(小分類)の id 群に展開する。
  # genre_id は小分類しか指さないため、上位を選んだら配下の小分類すべてで絞り込む。
  def genre_filter_ids
    return @genre_filter_ids if defined?(@genre_filter_ids)

    genre = genre_id && Genre.find_by(id: genre_id)
    @genre_filter_ids = genre && small_descendant_ids(genre)
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
