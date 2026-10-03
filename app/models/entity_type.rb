class EntityType < ApplicationRecord
  # エンティティタイプの単純マスタ(人名 / 書籍名 など)。語義から entity_type_id で参照される。
  include TagMaster

  # 語義から参照されている間はマスタとして削除させない(タグ統括管理の削除ガード)。
  has_many :word_senses, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  private

  # 統合: このタイプを付けている語義の FK を other に付け替える。
  def reassign_usages_to(other)
    # update_all は touch と after_commit を通らない(words.updated_at が進まないので、sitemap・llms-full の版は最長 1 日古いまま。
    # 詳細ページは Word#cache_dependencies が拾う)。代表値の列は変えないので WordSenseMetrics の焼き直しは要らない。
    WordSense.where(entity_type_id: id).update_all(entity_type_id: other.id)
  end
end
