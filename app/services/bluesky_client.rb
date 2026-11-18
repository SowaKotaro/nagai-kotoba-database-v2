# Bluesky(AT Protocol)へ投稿するクライアント。SNS の自動投稿(SnsBroadcast)が使う。
#
# - 認証はハンドルとアプリパスワード(docs/sns-autopost-setup.md §4)。投稿のたびにセッションを作り直す(毎時 1 回なので、トークンを持ち回らない)。
# - 本文を投稿し、その返信に単語詳細へのリンクを付ける。Bluesky はリンクのカードを自動では作らないので、
#   返信にリンクの facet(どのバイト範囲がリンクか)と、カード(app.bsky.embed.external。画像は共有カード)を付ける。
# - 返信だけが失敗しても、本文の投稿は成功として返す(error に理由を残す)。
# - 通信は Net::HTTP(gem を足さない)。タイムアウトを持ち、通信と応答の失敗は例外にせず Result の error で返す。
#   エラーの文言に認証情報を入れない。
#   仕様: https://docs.bsky.app/docs/advanced-guides/posts ・ https://docs.bsky.app/docs/api/com-atproto-server-create-session
# 種別: 外部 API のクライアント。
class BlueskyClient
  require "net/http"

  SERVICE = "https://bsky.social"
  # 秒。
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20
  # カードの画像(blob)の上限(バイト)。超えたら画像の無いカードにする。
  MAX_IMAGE_BYTES = 1_000_000

  # remote_id は本文の投稿の at:// URI(失敗したら nil)。error は失敗の理由か、返信だけ失敗したときの理由。
  Result = Data.define(:remote_id, :error) do
    def success? = remote_id.present?
  end

  Error = Class.new(StandardError)

  # 設定(config.x.sns_bluesky_*)が揃っていればクライアント、無ければ nil。
  def self.from_config
    config = Rails.application.config.x
    return if config.sns_bluesky_identifier.blank? || config.sns_bluesky_app_password.blank?

    new(identifier: config.sns_bluesky_identifier, app_password: config.sns_bluesky_app_password)
  end

  # transport はテストで差し替える。(uri, request) を受け取り Net::HTTPResponse を返す。
  def initialize(identifier:, app_password:, service: SERVICE, transport: method(:send_request))
    @identifier = identifier
    @app_password = app_password
    @service = service
    @transport = transport
  end

  def publish(message)
    session = xrpc("com.atproto.server.createSession", { identifier: @identifier, password: @app_password })
    post = create_post(session, { text: message.body })
    Result.new(remote_id: post.fetch("uri"), error: reply_with_link(session, post, message.link))
  rescue Error => e
    Result.new(remote_id: nil, error: e.message)
  rescue KeyError
    Result.new(remote_id: nil, error: "応答に必要な項目がありませんでした")
  end

  private

  # 返信に失敗したら、その理由(成功なら nil)。
  def reply_with_link(session, parent, link)
    reference = { uri: parent.fetch("uri"), cid: parent.fetch("cid") }
    create_post(session, {
      text: link.url,
      facets: [ link_facet(link.url, byte_start: 0) ],
      reply: { root: reference, parent: reference },
      embed: external_embed(session, link)
    })
    nil
  rescue Error, KeyError => e
    "返信: #{e.is_a?(KeyError) ? "応答に必要な項目がありませんでした" : e.message}"
  end

  def create_post(session, record)
    xrpc("com.atproto.repo.createRecord",
         { repo: session.fetch("did"), collection: "app.bsky.feed.post",
           record: { "$type": "app.bsky.feed.post", createdAt: Time.current.utc.iso8601(3), langs: [ "ja" ], **record } },
         token: session.fetch("accessJwt"))
  end

  # facet の位置は UTF-8 のバイトで数える。
  def link_facet(url, byte_start:)
    { index: { byteStart: byte_start, byteEnd: byte_start + url.bytesize },
      features: [ { "$type": "app.bsky.richtext.facet#link", uri: url } ] }
  end

  def external_embed(session, link)
    external = { uri: link.url, title: link.title, description: link.description }
    if link.image && link.image.bytesize <= MAX_IMAGE_BYTES
      external[:thumb] = xrpc("com.atproto.repo.uploadBlob", link.image,
                              token: session.fetch("accessJwt"), content_type: "image/png").fetch("blob")
    end
    { "$type": "app.bsky.embed.external", external: }
  end

  def xrpc(method_name, body, token: nil, content_type: "application/json")
    uri = URI("#{@service}/xrpc/#{method_name}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = content_type
    request["Authorization"] = "Bearer #{token}" if token
    request.body = content_type == "application/json" ? body.to_json : body
    response = @transport.call(uri, request)
    raise Error, "#{method_name}: HTTP #{response.code} #{error_name(response)}".strip unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue Timeout::Error, SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
    raise Error, "#{method_name}: #{e.class}"
  rescue JSON::ParserError
    raise Error, "#{method_name}: 応答を読めませんでした"
  end

  # 失敗の応答の { "error": "...", "message": "..." } から、名前だけを取る(本文をそのままログに出さない)。
  def error_name(response)
    JSON.parse(response.body.to_s)["error"].to_s
  rescue JSON::ParserError
    ""
  end

  def send_request(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, write_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end
  end
end
