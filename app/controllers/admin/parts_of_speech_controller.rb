# 品詞マスタのその場追加。
class Admin::PartsOfSpeechController < Admin::BaseController
  def create
    pos = PartOfSpeech.new(name: params[:name])
    if pos.save
      render json: { id: pos.id, name: pos.name }
    else
      render json: { errors: pos.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
