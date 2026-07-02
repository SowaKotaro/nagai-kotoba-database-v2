class EntityType < ApplicationRecord
  # エンティティタイプの単純マスタ(人名 / 書籍名 など)。
  validates :name, presence: true, uniqueness: true
end
