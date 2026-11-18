# SNS のクライアント(BlueskyClient・XClient)が共有する、結果の型と HTTP の送り方。
# クライアントは publish(message) で Result を返し、例外を外に投げない(SnsBroadcast が 1 つの SNS の失敗でほかを止めないため)。
# 種別: 外部 API のクライアント。
module SnsClient
  require "net/http"

  # 秒。
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20
  # 通信の失敗として Error に包む例外。
  NETWORK_ERRORS = [ Timeout::Error, SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse ].freeze

  # remote_id は本文の投稿の ID(失敗したら nil)。error は失敗の理由か、返信だけ失敗したときの理由。
  Result = Data.define(:remote_id, :error) do
    def success? = remote_id.present?
  end

  Error = Class.new(StandardError)

  module_function

  # 既定の送り方。クライアントは transport としてこれを持ち、テストで差し替える。
  def send_request(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, write_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end
  end
end
