# X(旧 Twitter)へ投稿するクライアント。SNS の自動投稿(SnsBroadcast)が使う。
#
# - 認証は OAuth 1.0a のユーザーの鍵(API Key・API Key Secret・Access Token・Access Token Secret。docs/sns-autopost-setup.md §2)。
#   鍵に期限は無い。署名(HMAC-SHA1)はここで作る(gem を足さない)。本文は JSON で送るので、署名には含めない。
# - 本文だけを投稿し、リンクの返信は付けない(X の API は URL を含む投稿が 1 件 0.20 ドルと高い。Issue 113)。
# - 料金はクレジットの前払い。残高が尽きると 402 が返り、投稿されないだけで課金は増えない。
# - 通信は Net::HTTP(SnsClient)。失敗は例外にせず SnsClient::Result の error で返す。エラーの文言に鍵を入れない。
#   仕様: https://docs.x.com/x-api/posts/create-post ・ https://docs.x.com/resources/fundamentals/authentication/oauth-1-0a/creating-a-signature
# 種別: 外部 API のクライアント。
class XClient
  ENDPOINT = "https://api.x.com/2/tweets"

  # 設定(config.x.sns_x_*)が 4 つとも揃っていればクライアント、無ければ nil。
  def self.from_config
    config = Rails.application.config.x
    keys = { api_key: config.sns_x_api_key, api_key_secret: config.sns_x_api_key_secret,
             access_token: config.sns_x_access_token, access_token_secret: config.sns_x_access_token_secret }
    return if keys.values.any?(&:blank?)

    new(**keys)
  end

  # OAuth 1.0a の署名(Base64 の HMAC-SHA1)。params は oauth_* と、署名に含める要求の引数。
  def self.signature(http_method, url, params, consumer_secret:, token_secret:)
    encoded = params.map { |key, value| [ percent_encode(key), percent_encode(value) ] }.sort.map { it.join("=") }.join("&")
    base = [ http_method.upcase, percent_encode(url), percent_encode(encoded) ].join("&")
    key = "#{percent_encode(consumer_secret)}&#{percent_encode(token_secret)}"
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", key, base))
  end

  # RFC 3986 の非予約文字(英数字と - . _ ~)のほかをすべて %XX にする。
  def self.percent_encode(value) = ERB::Util.url_encode(value.to_s)

  # transport はテストで差し替える。(uri, request) を受け取り Net::HTTPResponse を返す。
  def initialize(api_key:, api_key_secret:, access_token:, access_token_secret:, transport: SnsClient.method(:send_request))
    @api_key = api_key
    @api_key_secret = api_key_secret
    @access_token = access_token
    @access_token_secret = access_token_secret
    @transport = transport
  end

  # SnsClient::Result を返す。remote_id は投稿の ID。message.link は使わない。
  def publish(message)
    uri = URI(ENDPOINT)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = authorization_header("POST", ENDPOINT)
    request.body = { text: message.body }.to_json
    response = @transport.call(uri, request)
    return SnsClient::Result.new(remote_id: nil, error: "HTTP #{response.code} #{error_title(response)}".strip) unless response.is_a?(Net::HTTPSuccess)

    SnsClient::Result.new(remote_id: JSON.parse(response.body).dig("data", "id"), error: nil)
  rescue *SnsClient::NETWORK_ERRORS => e
    SnsClient::Result.new(remote_id: nil, error: e.class.name)
  rescue JSON::ParserError
    SnsClient::Result.new(remote_id: nil, error: "応答を読めませんでした")
  end

  private

  def authorization_header(http_method, url)
    oauth = { oauth_consumer_key: @api_key, oauth_nonce: SecureRandom.hex(16), oauth_signature_method: "HMAC-SHA1",
              oauth_timestamp: Time.now.to_i.to_s, oauth_token: @access_token, oauth_version: "1.0" }
    oauth[:oauth_signature] = self.class.signature(http_method, url, oauth, consumer_secret: @api_key_secret,
                                                                              token_secret: @access_token_secret)
    "OAuth " + oauth.map { |key, value| %(#{self.class.percent_encode(key)}="#{self.class.percent_encode(value)}") }.join(", ")
  end

  # 失敗の応答の { "title": "...", "detail": "..." } から、見出しだけを取る(本文をそのままログに出さない)。
  def error_title(response)
    JSON.parse(response.body.to_s)["title"].to_s
  rescue JSON::ParserError
    ""
  end
end
