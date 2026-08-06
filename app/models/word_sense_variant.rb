class WordSenseVariant < ApplicationRecord
  # 別表記。語義(word_sense)に 1:多 でぶら下がる従属的な別の表記。
  # 別表記は「その語義」にだけ付く(例:「バタフライエフェクト」の自然科学の語義の別表記
  # 「バタフライ効果」)。読みも変わりうるため reading を任意で保持する。
  # 別表記の数はランキング(variant_count_desc)の指標として words に非正規化してある。
  include RefreshesWordMetrics

  belongs_to :word_sense

  validates :surface, presence: true
  # 同じ語義に同じ表記を二重登録させない(DB の複合ユニークと二重で担保)。
  validates :surface, uniqueness: { scope: :word_sense_id }

  private

  # 代表値の焼き直し対象(RefreshesWordMetrics)。
  def resolve_metrics_word_id = word_sense&.word_id
end
