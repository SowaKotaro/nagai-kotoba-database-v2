# 単語詳細の「しりとり 〜次の一手〜」を組み立てるクエリオブジェクト。
# 代表(最小id)の語義の末尾文字を先頭文字に持つ公開語を数件返す。
#
# しりとりの慣習にあたる文字の畳み込みは、大半を既存の仕組みが担っている:
#   - 末尾の長音符「ー」は last_char の生成時にスキップ済み(app/models/last_char.rb)
#   - 照合順序 utf8mb4_0900_as_ci がひらがな⇔カタカナ・小書き⇔大書きを同一視するので、
#     「ャ」で終わる語は「ヤ」で始まる語に繋がる
#   - 清濁は as_ci でも区別されるため、「ガ」で終われば「ガ」始まりだけを次の手にする(厳密ルール)
class ShiritoriWords
  LIMIT = 6

  # しりとりが終わる文字(基本46字へ畳んだ表記)。
  DEAD_END_CHAR = "ン"

  def initialize(word)
    @word = word
    @sense = word.word_senses.min_by(&:id)
  end

  # 次の一手の起点になる文字(= 代表語義の末尾文字)。語義が無ければ nil。
  def head_char
    @sense&.last_char
  end

  # 「ん」で終わる語は、しりとりのルール上そこで終わり。
  def dead_end?
    KanaRow.base(head_char) == DEAD_END_CHAR
  end

  # 単語一覧(先頭文字での絞り込み)への導線。docs/design.md §5.5
  def facet_params
    { first_char: head_char }
  end

  # 次の一手の候補(該当が無ければ空)。
  def words
    @words ||= load_words
  end

  private

  def load_words
    return Word.none if head_char.blank? || dead_end?

    word_ids = WordSense.published.first_char_is(head_char).where.not(word_id: @word.id)
                        .order(:word_id).distinct.limit(LIMIT).pluck(:word_id)
    return Word.none if word_ids.empty?

    # 一覧行(words/_entry_row)がジャンル・品詞・エンティティも出すので先読みする
    Word.where(id: word_ids)
        .includes(word_senses: [ :part_of_speech, :entity_type, { genre: :parent } ])
        .order(:surface)
  end
end
