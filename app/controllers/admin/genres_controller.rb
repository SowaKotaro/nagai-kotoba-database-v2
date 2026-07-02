# ジャンルの大→中→小 依存ドロップダウン用のエンドポイント。
class Admin::GenresController < Admin::BaseController
  # 指定した親ジャンルの直下の子を JSON で返す(親未指定なら空)。
  # parent_id を省くと where(parent_id: nil) が大分類を返してしまうため明示的にガードする。
  def children
    return render json: [] if params[:parent_id].blank?

    genres = Genre.where(parent_id: params[:parent_id]).order(:name)
    render json: genres.pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end
end
