# 公開側から届いた収録リクエストの確認(Issue 75)。
#
# 一覧は語単位(WordRequestItem)で、送信の技術メタデータは通(WordRequest)側から辿る。
# 操作は「選択 → 一括」に寄せている。行ごとにフォームを置くと、選択用のフォームと
# 入れ子になってしまうため(既存の一括適用パネルと同じ作法)。
class Admin::WordRequestsController < Admin::BaseController
  PER_PAGE = 100
  # 一括登録へ渡せる語数の上限。箇条書きにして URL に載せて渡すため、長さを抑える。
  BULK_HANDOFF_LIMIT = 50

  def index
    @status = params[:status].presence_in(WordRequestItem.statuses.keys)
    @ip_address = params[:ip].presence
    @page = [ params[:page].to_i, 1 ].max

    scope = filtered_items
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @items = scope.includes(:word_request).recent_first
                  .limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
    @registered_surfaces = registered_surfaces_for(@items)
  end

  # 選択した語への一括操作。ボタンの commit で分岐する。
  def bulk
    items = WordRequestItem.where(id: params[:item_ids]).order(:id)
    return redirect_back_to_index(alert: t(".no_selection")) if items.empty?

    case params[:commit]
    when "to_bulk" then hand_off_to_bulk_registration(items)
    when "destroy" then destroy_selected(items)
    else apply_status(items)
    end
  end

  private

  def filtered_items
    scope = WordRequestItem.all
    scope = scope.where(status: @status) if @status
    scope = scope.where(word_request: WordRequest.where(ip_address: @ip_address)) if @ip_address
    scope
  end

  # 「投稿後に収録された語」を一覧で見分けるための集合(取りこぼし防止)。
  # 照合順序が as_ci のため、ひらがな・カタカナ違いも同じ語として一致する。
  def registered_surfaces_for(items)
    return Set.new if items.empty?

    Word.where(surface: items.map(&:surface)).pluck(:surface).to_set
  end

  # 選択した語の状態(と任意のメモ)をまとめて更新する。
  def apply_status(items)
    status = params[:status_to].presence_in(WordRequestItem.statuses.keys)
    return redirect_back_to_index(alert: t(".no_status")) if status.blank?

    attributes = { status: status }
    memo = params[:admin_memo].to_s.strip
    attributes[:admin_memo] = memo if memo.present?

    # handled_at を打つコールバックを通すため update_all は使わない(件数は数十件程度)。
    count = items.count
    items.find_each { |item| item.update!(attributes) }
    redirect_back_to_index(notice: t(".applied", count: count))
  end

  # 選択した語を一括登録の step1(箇条書き)へ流し込む。ここが収録までの主動線。
  def hand_off_to_bulk_registration(items)
    surfaces = items.limit(BULK_HANDOFF_LIMIT).pluck(:surface)
    flash[:alert] = t(".limited", count: BULK_HANDOFF_LIMIT) if items.count > BULK_HANDOFF_LIMIT
    redirect_to new_admin_word_path(text: surfaces.join("\n"))
  end

  def destroy_selected(items)
    count = items.count
    items.destroy_all
    redirect_back_to_index(notice: t(".destroyed", count: count))
  end

  # 絞り込みとページを保ったまま一覧へ戻す。
  def redirect_back_to_index(**flash_options)
    redirect_to admin_requests_path(params.permit(:status, :ip, :page).to_h.compact_blank), **flash_options
  end
end
