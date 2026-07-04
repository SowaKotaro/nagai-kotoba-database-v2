class WordOrigin < ApplicationRecord
  # 語種の単純マスタ(和語 / 漢語 / 英語 / フランス語 …)。語義とは多対多。
  # 語義から参照されている語種はマスタとして削除させない。
  has_many :word_sense_origins, dependent: :restrict_with_error
  has_many :word_senses, through: :word_sense_origins

  validates :name, presence: true, uniqueness: true
end
