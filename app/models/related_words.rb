# 単語詳細の「関連語」を組み立てるクエリオブジェクト(Issue 23)。
# 代表(最小id)の語義を起点に、同じ小分類ジャンル / 同じ読みの文字数 /
# 同じ先頭文字 の語を各数件返す。自身は除外し、インデックス済みカラムのみ・
# 決定的な順序で引く(N+1 を避けるため関連は includes 済み)。
class RelatedWords
  LIMIT = 6

  Group = Struct.new(:key, :facet_params, :words)

  def initialize(word)
    @word = word
    @sense = word.word_senses.min_by(&:id)
  end

  # 表示するグループの配列(該当が無いグループは含めない)。
  def groups
    return [] if @sense.nil?

    [ genre_group, reading_length_group, first_char_group ].compact
  end

  private

  def genre_group
    return nil unless @sense.genre_id

    build(:genre, { genre_id: @sense.genre_id }, matching_senses.where(genre_id: @sense.genre_id))
  end

  def reading_length_group
    build(:reading_length, { reading_length: @sense.reading_length },
          matching_senses.where(reading_length: @sense.reading_length))
  end

  def first_char_group
    return nil if @sense.first_char.blank?

    build(:first_char, { first_char: @sense.first_char }, matching_senses.where(first_char: @sense.first_char))
  end

  # 公開(注釈済み)で、自身を除いた語義。
  def matching_senses
    WordSense.published.where.not(word_id: @word.id)
  end

  def build(key, facet_params, sense_scope)
    word_ids = sense_scope.order(:word_id).distinct.limit(LIMIT).pluck(:word_id)
    return nil if word_ids.empty?

    words = Word.where(id: word_ids)
                .includes(word_senses: [ :part_of_speech, :entity_type ])
                .order(:surface)
    Group.new(key, facet_params, words)
  end
end
