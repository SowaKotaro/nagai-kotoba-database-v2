# 単語詳細の複数の区画(関連語の各グループ・しりとり)が出す語を、まとめて1回で読み込む(Issue 87)。
#
# 区画ごとに Word.where(id:).includes(...) を引くと、同じ先読み(語義・エンティティ・ジャンルの祖先3段)が
# 区画の数だけ走る。各区画は先に reserve で word_id を預けておき、最初に語を求められた時点で
# 預かった id をまとめて読み込んで配り直す。
class WordBatch
  # 一覧行(words/_entry_row)がジャンルのパンくず・エンティティを出すので、祖先まで先読みする
  PRELOAD = { word_senses: [ :entity_type, { genre: { parent: :parent } } ] }.freeze

  def initialize
    @reserved_ids = []
    @loaded = nil
  end

  # 後で words_for で取り出す id を預ける。受け取った id をそのまま返す。
  def reserve(ids)
    @reserved_ids |= ids
    @loaded = nil unless ids.all? { |id| loaded_ids.include?(id) }
    ids
  end

  # 預けた id のうち ids に当たる語を、表層形の順(照合順序は DB に任せる)で返す。
  def words_for(ids)
    return [] if ids.empty?

    wanted = ids.to_set
    loaded.select { |word| wanted.include?(word.id) }
  end

  private

  def loaded
    @loaded ||= Word.where(id: @reserved_ids).includes(PRELOAD).order(:surface).to_a
  end

  def loaded_ids
    @loaded ? @loaded.map(&:id) : []
  end
end
