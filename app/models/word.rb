class Word < ApplicationRecord
  # 1つの表層形に対し複数の語義を持つ(同音異義語に対応)。
  has_many :word_senses, dependent: :destroy
  # 管理画面から語義をネストして登録・編集する。空行はスキップ、_destroy で削除可。
  accepts_nested_attributes_for :word_senses, allow_destroy: true, reject_if: :all_blank

  validates :surface, presence: true, uniqueness: true

  # char_type_pattern は surface から常に導出する(手入力させない)。
  before_validation :assign_char_type_pattern

  private

  def assign_char_type_pattern
    self.char_type_pattern = CharTypePattern.call(surface)
  end
end
