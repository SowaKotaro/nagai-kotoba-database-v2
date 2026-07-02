class PartOfSpeech < ApplicationRecord
  # 品詞の単純マスタ。テーブル名は parts_of_speech(不規則複数形。config/initializers/inflections.rb 参照)。
  validates :name, presence: true, uniqueness: true
end
