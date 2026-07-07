class WordSenseFeature < ApplicationRecord
  # 語義 × 言語学的特徴の多対多をつなぐ中間モデル。
  # 特徴は単語の「該当部分」ごとに付与する(例:「硫黄島からの手紙」に 連濁:硫黄島 と 連濁:手紙)。
  # target_start は該当部分の出現位置(表層形の先頭からの文字オフセット・0始まり)で、
  # 同じ表層形に同じ target が繰り返し現れる語(例「びしょびしょ…びしょびしょ…」)に、
  # 同じ特徴を出現箇所ごとに複数付与できるようにする識別子。
  belongs_to :word_sense
  belongs_to :linguistic_feature

  # target_start は未指定なら最初の出現位置に補完する(通常はフォームが出現位置を送る)。
  before_validation :derive_target_start, if: -> { target_start.nil? && target.present? }

  validates :target, presence: true
  validates :target_reading, presence: true
  validates :target_start, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: false
  # 同じ語義×特徴でも「該当部分＋出現位置」が違えば複数登録できる。四つ組の重複だけを
  # 禁止する(DB の複合ユニークと二重で担保)。
  validates :target, uniqueness: { scope: [ :word_sense_id, :linguistic_feature_id, :target_start ] }
  validate :target_within_surface
  validate :target_reading_within_reading

  private

  # 出現位置が渡されなかったとき、表層形内の最初の出現位置を採る(見つからなければ0)。
  def derive_target_start
    self.target_start = word_sense&.word&.surface.to_s.index(target) || 0
  end

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
