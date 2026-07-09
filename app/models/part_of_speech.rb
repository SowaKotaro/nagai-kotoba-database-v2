class PartOfSpeech < ApplicationRecord
  # 品詞の単純マスタ。テーブル名は parts_of_speech(不規則複数形。config/initializers/inflections.rb 参照)。
  # 語義から part_of_speech_id で参照される。
  include TagMaster

  # 語義から参照されている間はマスタとして削除させない(タグ統括管理の削除ガード)。
  has_many :word_senses, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  private

  # 統合: この品詞を付けている語義の FK を other に付け替える。
  def reassign_usages_to(other)
    WordSense.where(part_of_speech_id: id).update_all(part_of_speech_id: other.id)
  end
end
