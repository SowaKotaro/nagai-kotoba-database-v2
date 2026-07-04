class WordSenseOrigin < ApplicationRecord
  # 語義 × 語種 の多対多をつなぐ中間モデル。
  # 混種語(例: 歯ブラシ = 和語 + 英語)に対応するため 1 語義に複数の語種を付与できる。
  belongs_to :word_sense
  belongs_to :word_origin

  # 同じ語義に同じ語種を二重登録させない(DB の複合ユニークと二重で担保)。
  validates :word_origin_id, uniqueness: { scope: :word_sense_id }
end
