# 単語詳細の「しりとり 〜次の一手〜」を組み立てるクエリオブジェクト。
# 代表(最小id)の語義の末尾文字を先頭文字に持つ公開語を数件返す。
# どの数件を出すかは語ごとに窓をずらす(WordWindow。毎回同じ手が返ると遊びにならない。Issue 86)。
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

  # batch を関連語(RelatedWords)と共有すると、両区画の語を1回で読み込む(Issue 87)。
  # そのため候補の id はここで確定させて預けておく(描画より前に預けないと2回読みになる)。
  def initialize(word, batch: WordBatch.new)
    @word = word
    @batch = batch
    @sense = word.word_senses.min_by(&:id)
    @word_ids = @batch.reserve(candidate_word_ids)
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
    @batch.words_for(@word_ids)
  end

  private

  def candidate_word_ids
    return [] if head_char.blank? || dead_end?

    candidates = WordSense.published.first_char_is(head_char).where.not(word_id: @word.id)
    WordWindow.word_ids(candidates, pivot_id: @word.id, limit: LIMIT)
  end
end
