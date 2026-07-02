class WordSense < ApplicationRecord
  # 1つの表層形(word)に複数の語義がぶら下がる(同音異義語に対応)。
  belongs_to :word
  # genre_id は末端(小分類=level3)を指す。entity_type / part_of_speech は任意。
  belongs_to :genre, optional: true
  belongs_to :entity_type, optional: true
  belongs_to :part_of_speech, optional: true
  # ※言語学的特徴との多対多(word_sense_features 経由)は Issue 6 で追加する。

  validates :reading, presence: true
  validate :genre_must_be_small

  # rhythm_pattern は reading から常に導出する(手入力させない)。
  before_validation :assign_rhythm_pattern

  private

  def assign_rhythm_pattern
    self.rhythm_pattern = RhythmPattern.call(reading)
  end

  # genre は必ず小分類(末端)を指す運用。大・中分類は登録できない。
  def genre_must_be_small
    return if genre.blank?

    errors.add(:genre, :must_be_small) unless genre.small?
  end
end
