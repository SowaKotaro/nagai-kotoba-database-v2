# タグ統括管理。ジャンル・エンティティタイプ・品詞・語種・言語学的特徴の各マスタ(=タグ)を
# 横断して、一覧・名前の編集(リネーム)・未使用タグの削除・別タグへの統合を行う。
# タグは語義から外部キー/中間表で参照されるため、名前を変えれば付与済みの全データに反映される。
# :kind は TagKind のホワイトリストで解決し、未知の種別は 404 にする(任意モデルを掴ませない)。
class Admin::TagsController < Admin::BaseController
  before_action :set_kind, except: :index

  # ハブ。5種のマスタと登録件数の一覧。
  def index
    @kinds = TagKind.all
  end

  # 1種別のタグ一覧(使用件数つき)。
  def show
    @records = @kind.records.to_a
    @usage_counts = @kind.usage_counts
    @deletable_ids = @kind.deletable_ids(@records, @usage_counts)
    # ジャンルは親名の表示に使う(id => レコードの索引。N+1 回避)。
    @genre_index = @records.index_by(&:id) if @kind.hierarchical?
  end

  def edit
    @record = @kind.find_record(params[:id])
  end

  # リネーム。FK 参照なので、名前を変えると付与済みの全語義に反映される。
  def update
    @record = @kind.find_record(params[:id])
    if @record.update(tag_params)
      redirect_to admin_tag_kind_path(@kind.key), notice: t("admin.tags.flash.updated", name: @record.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 削除。未使用(参照なし・ジャンルは子も持たない)のときだけ許可する。
  def destroy
    record = @kind.find_record(params[:id])
    name = record.name
    if record.deletable? && record.destroy
      redirect_to admin_tag_kind_path(@kind.key), notice: t("admin.tags.flash.destroyed", name: name)
    else
      redirect_to admin_tag_kind_path(@kind.key), alert: t("admin.tags.flash.destroy_blocked", name: name)
    end
  end

  # 統合。source を付けている全データを target に付け替え、source を削除する。
  def merge
    if params[:source_id].blank? || params[:target_id].blank?
      return redirect_to admin_tag_kind_path(@kind.key), alert: t("admin.tags.flash.merge_no_target")
    end

    source = @kind.find_record(params[:source_id])
    target = @kind.find_record(params[:target_id])
    source_name = source.name
    source.merge_into!(target)
    redirect_to admin_tag_kind_path(@kind.key), notice: t("admin.tags.flash.merged", source: source_name, target: target.name)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to admin_tag_kind_path(@kind.key), alert: t("admin.tags.flash.merge_failed", message: e.message)
  end

  private

  def set_kind
    @kind = TagKind.find(params[:kind])
  end

  # どの種別でもフォームは tag[name] で受ける(単一コントローラのため)。
  def tag_params
    params.require(:tag).permit(:name)
  end
end
