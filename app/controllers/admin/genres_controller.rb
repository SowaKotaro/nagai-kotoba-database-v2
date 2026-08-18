# ジャンルの大→中→小 依存選択用のエンドポイント。
class Admin::GenresController < Admin::BaseController
  include InlineMasterCreatable

  # 指定した親ジャンルの直下の子を JSON で返す(親未指定なら空)。
  # parent_id を省くと where(parent_id: nil) が大分類を返してしまうため明示的にガードする。
  def children
    return render json: [] if params[:parent_id].blank?

    genres = Genre.where(parent_id: params[:parent_id]).order(:name)
    render json: genres.pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end

  # ジャンルのその場追加。親未指定なら大分類、親が大なら中分類、親が中なら小分類として作る。
  # 同じ親の下に同名が既にあれば作らずにそれを返す(UI 側はそのまま選択する)。
  def create
    parent = Genre.find(params[:parent_id]) if params[:parent_id].present?
    level = if parent.nil? then :large elsif parent.large? then :medium else :small end
    create_inline_master(Genre.where(parent_id: parent&.id), level: level)
  end
end
