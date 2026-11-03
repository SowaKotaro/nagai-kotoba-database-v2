# エンティティ(作品名・キャラクター名・駅名 など、その言葉が何の名前か)から探すページ。誰でも閲覧できる。
# 「長い駅名」「長い曲名」のように何の名前かで探す人が、1 回押せば一覧へ行けるようにする
# (詳細検索ではエンティティのチップが登録順に、件数なしで並ぶ)。
class EntityTypesController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    # 集計は公開語義の全件走査なので、索引と同じ PublishedSenseCounts のキャッシュを引く。
    @counts = PublishedSenseCounts.by_entity_type
    # 公開語義のあるものだけを、語の多い順に並べる。0 件のものは選んでも空の一覧になるので出さない(/genres と同じ)。
    @entity_types = EntityType.ordered_by_published_count(@counts)
  end
end
