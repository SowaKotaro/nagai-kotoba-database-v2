class LinguisticFeature < ApplicationRecord
  # 言語学的特徴の単純マスタ(連濁 / 重箱読み / 湯桶読み など)。語義とは多対多。
  # 語義から参照されている特徴はマスタとして削除させない。
  has_many :word_sense_features, dependent: :restrict_with_error
  has_many :word_senses, through: :word_sense_features

  validates :name, presence: true, uniqueness: true
end
