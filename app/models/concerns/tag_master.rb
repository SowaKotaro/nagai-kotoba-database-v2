# タグとして扱う単純マスタ(エンティティタイプ / 品詞 / 語種 / 言語学的特徴)に共通の振る舞い。
# 「タグの統括管理」画面から、使用件数の把握・未使用タグの削除・別タグへの統合を行うための IF を提供する。
# 階層を持つ Genre は都合が異なるため、この concern を使わず独自に同じ IF を実装する。
module TagMaster
  extend ActiveSupport::Concern

  # このタグを付けている語義の数(使用件数)。
  # has_many :word_senses(直接 or through)を各モデルが宣言している前提。
  def usage_count
    word_senses.distinct.count
  end

  # 未使用(どの語義にも付いていない)なら削除できる。
  def deletable?
    usage_count.zero?
  end

  # このタグ(self)を other へ統合する。
  # self を付けている全語義を other に付け替えたうえで self を削除する。
  # 付け替えの実体は各モデルの reassign_usages_to(other) が担う(FK 更新 or 中間表の重複回避つき更新)。
  def merge_into!(other)
    raise ArgumentError, "同じタグには統合できません" if other.id == id
    raise ArgumentError, "種類の違うタグには統合できません" unless other.instance_of?(self.class)

    transaction do
      reassign_usages_to(other)
      # 付け替え後の状態で削除ガード(restrict)を通すため、キャッシュした関連を捨てる。
      reload
      destroy!
    end
  end
end
