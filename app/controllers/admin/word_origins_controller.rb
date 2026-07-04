# 語種マスタのその場追加(コンソールから画面遷移せずに選択肢を増やす)。
class Admin::WordOriginsController < Admin::BaseController
  def create
    origin = WordOrigin.new(name: params[:name])
    if origin.save
      render json: { id: origin.id, name: origin.name }
    else
      render json: { errors: origin.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
