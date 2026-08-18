# エンティティタイプ マスタのその場追加。
class Admin::EntityTypesController < Admin::BaseController
  include InlineMasterCreatable

  def create
    create_inline_master(EntityType.all)
  end
end
