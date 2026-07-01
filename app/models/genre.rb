class Genre < ApplicationRecord
  # 大(1)→中(2)→小(3) の3階層。word_senses.genre_id は末端(小分類)を指す。
  LEVELS = { large: 1, medium: 2, small: 3 }.freeze
  enum :level, LEVELS

  # 自己参照の隣接リスト。level1(大分類)は親を持たない。
  belongs_to :parent, class_name: "Genre", optional: true
  has_many :children, class_name: "Genre", foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_error

  validates :name, presence: true
  # 同じ親の下では同名を許さない。level1(parent_id=NULL)の重複は DB の UNIQUE では
  # 防げないため、ここで scope: :parent_id により担保する。
  validates :name, uniqueness: { scope: :parent_id }
  validate :parent_matches_level

  # 末端(自身)から祖先を辿り、大→中→小の順に並べた配列を返す。
  # 例: 小分類なら [大, 中, 小]。
  def self_and_ancestors
    chain = [ self ]
    node = self
    chain.unshift(node) while (node = node.parent)
    chain
  end

  # 大分類(root)を返す。
  def root_genre
    self_and_ancestors.first
  end

  private

  # level と parent の整合性を検証する。
  #   level1(大): 親を持たない
  #   level2/3   : 親が必須で、親の level は自身の level から1つ上（数値-1）
  def parent_matches_level
    return if level.blank?

    if large?
      errors.add(:parent, :must_be_blank_for_large) if parent_id.present?
    elsif parent.nil?
      errors.add(:parent, :required_for_non_large)
    elsif LEVELS[parent.level.to_sym] != LEVELS[level.to_sym] - 1
      errors.add(:parent, :level_mismatch)
    end
  end
end
