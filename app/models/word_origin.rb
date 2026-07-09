class WordOrigin < ApplicationRecord
  # 語種の単純マスタ(和語 / 漢語 / 英語 / フランス語 …)。語義とは多対多。
  # 語義から参照されている語種はマスタとして削除させない。
  include TagMaster

  has_many :word_sense_origins, dependent: :restrict_with_error
  has_many :word_senses, through: :word_sense_origins

  validates :name, presence: true, uniqueness: true

  private

  # 統合: この語種を付けている中間表(word_sense_origins)を other に付け替える。
  # (word_sense_id, word_origin_id) はユニークなので、付け替え先に既に同じ語義があれば
  # 重複を作らずに元の行を捨てる。
  def reassign_usages_to(other)
    word_sense_origins.find_each do |link|
      if WordSenseOrigin.exists?(word_sense_id: link.word_sense_id, word_origin_id: other.id)
        link.destroy!
      else
        link.update!(word_origin_id: other.id)
      end
    end
  end
end
