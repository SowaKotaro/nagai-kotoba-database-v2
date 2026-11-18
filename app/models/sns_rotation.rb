# SNS の自動投稿で次の枠に出す語を選ぶ。公開語をランダムな順に出し、一巡するまで同じ語を重ねない
# (巡は sns_slots.round。途中で公開した語も、その巡のうちに出る)。本文が X の上限に収まらない語(SnsPostText.fits?)は出さない。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class SnsRotation
  # 本文が収まるかを確かめるために、一度に読み込む語の数。
  BATCH_SIZE = 50

  Pick = Data.define(:word, :round)

  def initialize(random: Random.new)
    @random = random
  end

  # Pick(語義を読み込んだ語と巡)。出せる語が 1 つも無ければ nil。
  def call
    round = SnsSlot.maximum(:round) || 1
    pick_from(round, excluded_ids: SnsSlot.where(round:).where.not(word_id: nil).pluck(:word_id)) ||
      # 巡の変わり目で、直前に出した語がまた出ないようにする。
      pick_from(round + 1, excluded_ids: SnsSlot.order(slot_at: :desc).limit(1).pluck(:word_id).compact)
  end

  private

  def pick_from(round, excluded_ids:)
    candidate_ids = Word.annotated.where.not(id: excluded_ids).ids.shuffle(random: @random)
    candidate_ids.each_slice(BATCH_SIZE) do |ids|
      words = Word.where(id: ids).includes(:word_senses).index_by(&:id)
      word = ids.filter_map { words[it] }.find { SnsPostText.fits?(it) }
      return Pick.new(word:, round:) if word
    end
    nil
  end
end
