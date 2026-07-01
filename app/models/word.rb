class Word < ApplicationRecord
  # 1つの表層形に対し複数の語義を持つ(同音異義語に対応)。※word_senses は Issue 5 で作成。
  has_many :word_senses, dependent: :destroy

  validates :surface, presence: true, uniqueness: true

  # char_type_pattern は surface から常に導出する(手入力させない)。
  before_validation :assign_char_type_pattern

  private

  def assign_char_type_pattern
    self.char_type_pattern = CharTypePattern.call(surface)
  end
end
