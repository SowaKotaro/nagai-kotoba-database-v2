class Genre < ApplicationRecord
  # 大(1)→中(2)→小(3) の3階層。word_senses.genre_id は末端(小分類)を指す。
  LEVELS = { large: 1, medium: 2, small: 3 }.freeze
  enum :level, LEVELS

  # 自己参照の隣接リスト。level1(大分類)は親を持たない。
  belongs_to :parent, class_name: "Genre", optional: true
  has_many :children, class_name: "Genre", foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_error
  # 小分類(末端)は語義から genre_id で参照される。参照中は削除させない(タグ統括管理の削除ガード)。
  has_many :word_senses, dependent: :restrict_with_error

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

  # --- タグ統括管理の共通 IF(TagMaster と同じ役割。階層があるため独自実装) ---

  # 自身と全子孫の id(高々3階層なので反復は最大2回)。
  def self_and_descendant_ids
    ids = [ id ]
    frontier = [ id ]
    until frontier.empty?
      frontier = Genre.where(parent_id: frontier).pluck(:id)
      ids.concat(frontier)
    end
    ids
  end

  # 使用件数。小分類は直接付いている語義数、中・大は配下の小分類に付く語義数の合計。
  def usage_count
    WordSense.where(genre_id: self_and_descendant_ids).count
  end

  # 子を持たず、自身にも語義が付いていなければ削除できる。
  def deletable?
    children.empty? && word_senses.empty?
  end

  # このジャンル(self)を同じ階層の other へ統合する。
  # 直下の子は other の下へ移し(同名の子があれば子同士を再帰統合)、
  # 小分類なら語義の genre_id を other へ付け替えてから self を削除する。
  def merge_into!(other)
    raise ArgumentError, "同じジャンルには統合できません" if other.id == id
    raise ArgumentError, "同じ階層のジャンル同士でのみ統合できます" unless other.instance_of?(Genre) && other.level == level

    transaction do
      children.to_a.each do |child|
        twin = other.children.find_by(name: child.name)
        twin ? child.merge_into!(twin) : child.update!(parent: other)
      end
      WordSense.where(genre_id: id).update_all(genre_id: other.id) if small?
      reload
      destroy!
    end
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
