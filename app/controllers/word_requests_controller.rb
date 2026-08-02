# 公開側からの収録リクエスト受付(Issue 75)。
#
# 閲覧専用だった公開面に開ける唯一の書き込み経路なので、防御はこのクラスに集める:
#   - ハニーポット(人間には見えない欄)と時間トラップ(WordRequestFormToken)
#   - 送信のレートリミットは保存済みレコードの COUNT(WordRequest.rate_limited?)
#   - 重複チェックはレコードを作らないため、そこだけ Rails 標準の rate_limit
#
# フォームは専用ページにだけ置く。単語一覧などは public: true の HTTP キャッシュ配下にあり、
# CSRF トークンを含むフォームを共有キャッシュに載せると別の利用者へトークンが渡るため、
# 検索0件などからは「リンク」で誘導する(このページ自体はキャッシュさせない)。
class WordRequestsController < ApplicationController
  allow_unauthenticated_access
  before_action :ensure_accepting_requests

  # ハニーポット。CSS で隠した欄で、人間は触れない = 埋まっていれば自動投稿。
  HONEYPOT_FIELD = :website

  # 重複チェック専用のカウンタ置き場。Rails.cache は環境によって :null_store
  # (test・キャッシュ無効時の development)になり、そこでは回数を数えられず制限が
  # 素通りしてしまうため、この用途だけプロセス内の小さなストアを持つ。
  # 将来 Rails.cache がプロセス間で共有されるストア(Solid Cache 等)になったら、
  # worker をまたいで数えられるようそちらへ移す。
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)

  # 重複チェックは既存語との総当たりを公開面に開くことになるので、押下自体を抑える。
  # (送信と違い保存レコードが残らず、created_at の COUNT では数えられないため)
  rate_limit to: 10, within: 1.minute, only: :duplicates,
             store: RATE_LIMIT_STORE, with: -> { render_check_throttled }

  def new
    @word_request = WordRequest.new
    @word_request.items.build(surface: prefilled_surface)
    @origin_path = origin_path_from_referer
  end

  def create
    return silently_accept if honeypot_filled?

    case WordRequestFormToken.verify(params[:form_token])
    when :too_fast then return silently_accept
    when :invalid then return reject_with(t(".expired"))
    end

    return reject_with(t(".rate_limited"), status: :too_many_requests) if rate_limited?

    @word_request = WordRequest.new(word_request_params.merge(submission_metadata))
    if @word_request.save
      redirect_to new_request_path, notice: t(".created")
    else
      restore_form
      render :new, status: :unprocessable_entity
    end
  end

  # 送信前の任意チェック。重複していても送信は妨げないため、ここでは保存も判定の記録もしない。
  # 結果は入力欄と同じ表の中へ返す(別の区画を開いて送信ボタンを遠ざけないため)。
  def duplicates
    restore_checked_form
    @results = WordRequestDuplicateCheck.new(duplicate_queries).call.index_by(&:surface)
    render :duplicates, layout: false
  end

  private

  def ensure_accepting_requests
    return if Rails.application.config.x.requests_enabled

    redirect_to about_path, alert: t("word_requests.closed")
  end

  def word_request_params
    params.require(:word_request).permit(items_attributes: %i[surface reading])
  end

  # 重複チェックは表層形と読みだけ見る(ひとことは判定に使わない)。
  def duplicate_queries
    attributes = params.fetch(:word_request, {}).permit(items_attributes: %i[surface reading])
    attributes.fetch(:items_attributes, {}).values.map do |item|
      { surface: item[:surface], reading: item[:reading] }
    end
  end

  def honeypot_filled? = params[HONEYPOT_FIELD].present?

  def rate_limited? = WordRequest.rate_limited?(request.remote_ip)

  # 罠に掛かった送信は、手口を知らせないために成功時と同じ画面を返して黙って捨てる。
  def silently_accept
    redirect_to new_request_path, notice: t("word_requests.create.created")
  end

  # 入力を保持したままフォームへ戻す(書いた内容を失わせない)。
  def reject_with(message, status: :unprocessable_entity)
    @word_request = WordRequest.new(word_request_params)
    restore_form
    flash.now[:alert] = message
    render :new, status: status
  end

  def restore_form
    @word_request.items.build if @word_request.items.empty?
    @origin_path = params[:origin_path]
  end

  def render_check_throttled
    @throttled = true
    restore_checked_form
    render :duplicates, layout: false, status: :too_many_requests
  end

  # 重複チェックは表ごと差し替えるので、入力された内容を組み直してから描き直す。
  def restore_checked_form
    @word_request = WordRequest.new(word_request_params)
    @word_request.items.build if @word_request.items.empty?
  end

  # 検索結果0件からの導線で渡されるキーワード。
  def prefilled_surface
    params[:surface].to_s.strip.slice(0, WordRequestItem::MAX_SURFACE_LENGTH).presence
  end

  def submission_metadata
    {
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.slice(0, 512),
      referer: request.referer&.slice(0, 1024),
      origin_path: params[:origin_path].presence&.slice(0, 1024)
    }
  end

  # フォームを開いた時点の直前ページ(自サイト内のパスのみ)。送信時の referer は
  # リクエストページ自身になるため、new で拾って hidden で持ち回す。
  def origin_path_from_referer
    referer = request.referer
    return nil if referer.blank?

    uri = URI.parse(referer)
    return nil unless uri.host.nil? || uri.host == request.host

    [ uri.path, uri.query ].compact_blank.join("?")
  rescue URI::InvalidURIError
    nil
  end
end
