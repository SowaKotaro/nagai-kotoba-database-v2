class LinguisticFeature < ApplicationRecord
  # 言語学的特徴の単純マスタ(連濁 / 重箱読み / 湯桶読み など)。※語義とは多対多(Issue 6)。
  validates :name, presence: true, uniqueness: true
end
