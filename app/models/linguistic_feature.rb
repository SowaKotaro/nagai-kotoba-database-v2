class LinguisticFeature < ApplicationRecord
  # 言語学的特徴の単純マスタ(連濁 / 重箱読み / 湯桶読み など)。語義とは多対多。
  # 語義から参照されている特徴はマスタとして削除させない。
  include TagMaster

  has_many :word_sense_features, dependent: :restrict_with_error
  has_many :word_senses, through: :word_sense_features

  validates :name, presence: true, uniqueness: true

  private

  # 統合: この特徴を付けている中間表(word_sense_features)を other に付け替える。
  # (word_sense_id, linguistic_feature_id, target, target_start) がユニークなので、
  # 付け替え先に同じ該当部分の行が既にあれば重複を作らずに元の行を捨てる。
  def reassign_usages_to(other)
    word_sense_features.find_each do |link|
      duplicate = WordSenseFeature.exists?(
        word_sense_id: link.word_sense_id,
        linguistic_feature_id: other.id,
        target: link.target,
        target_start: link.target_start
      )
      if duplicate
        link.destroy!
      else
        link.update!(linguistic_feature_id: other.id)
      end
    end
  end
end
