class WordSenseFeature < ApplicationRecord
  # 語義 × 言語学的特徴の多対多をつなぐ中間モデル。
  # 特徴は単語の「該当部分」ごとに付与する(例:「硫黄島からの手紙」に 連濁:硫黄島 と 連濁:手紙)。
  belongs_to :word_sense
  belongs_to :linguistic_feature

  validates :target, presence: true
  validates :target_reading, presence: true
  # 同じ語義×特徴でも該当部分が違えば複数登録できる。三つ組の重複だけを禁止する
  # (DB の複合ユニークと二重で担保)。
  validates :target, uniqueness: { scope: [ :word_sense_id, :linguistic_feature_id ] }
  validate :target_within_surface
  validate :target_reading_within_reading

  private

  # target は親 word の表層形(surface)の一部でなければならない。
  def target_within_surface
    return if target.blank? || word_sense&.word.nil?

    errors.add(:target, :not_in_surface) unless word_sense.word.surface.to_s.include?(target)
  end

  # target_reading は語義の読み(reading)の一部でなければならない。
  def target_reading_within_reading
    return if target_reading.blank? || word_sense.nil?

    errors.add(:target_reading, :not_in_reading) unless word_sense.reading.to_s.include?(target_reading)
  end
end
