# エンティティタイプ マスタのその場追加。
class Admin::EntityTypesController < Admin::BaseController
  def create
    entity_type = EntityType.new(name: params[:name])
    if entity_type.save
      render json: { id: entity_type.id, name: entity_type.name }
    else
      render json: { errors: entity_type.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
