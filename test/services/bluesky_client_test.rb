require "test_helper"

# Bluesky には送らず、送るはずだった要求を記録して、決めた応答を返す。
class BlueskyClientTest < ActiveSupport::TestCase
  LINK = SnsPostText::Link.new(url: "https://nagai-kotoba-database.jp/words/1", title: "寿限無", description: "落語", image: "PNG")
  MESSAGE = SnsPostText::Message.new(body: "寿限無\nジュゲム（4文字）", link: LINK)


  def http(status, body)
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s)
    klass.new("1.1", status.to_s, "").tap do |response|
      response.instance_variable_set(:@body, body.to_json)
      response.instance_variable_set(:@read, true)
    end
  end

  # 呼ばれた順に responses を返し、要求を requests に貯める。
  def client(responses, requests)
    transport = lambda do |uri, request|
      requests << [ uri.path.delete_prefix("/xrpc/"), request ]
      result = responses.shift
      result.is_a?(Exception) ? raise(result) : result
    end
    BlueskyClient.new(identifier: "nagaikotoba-bot.bsky.social", app_password: "secret-app-password", transport:)
  end

  def session = http(200, { did: "did:plc:abc", accessJwt: "jwt" })

  test "セッションを作って本文を投稿し、返信にリンクの facet と共有カードの画像つきのカードを付ける" do
    requests = []
    result = client([ session, http(200, { uri: "at://post", cid: "c1" }), http(200, { blob: { ref: "b" } }),
                      http(200, { uri: "at://reply", cid: "c2" }) ], requests).publish(MESSAGE)

    assert_equal BlueskyClient::Result.new(remote_id: "at://post", error: nil), result
    assert_equal %w[com.atproto.server.createSession com.atproto.repo.createRecord com.atproto.repo.uploadBlob
                    com.atproto.repo.createRecord], requests.map(&:first)
    assert_equal({ "identifier" => "nagaikotoba-bot.bsky.social", "password" => "secret-app-password" },
                 JSON.parse(requests[0].last.body))

    post = JSON.parse(requests[1].last.body)
    assert_equal "Bearer jwt", requests[1].last["Authorization"]
    assert_equal [ "did:plc:abc", "app.bsky.feed.post", MESSAGE.body ], [ post["repo"], post["collection"], post.dig("record", "text") ]
    assert_nil post.dig("record", "reply")

    assert_equal [ "image/png", "PNG" ], [ requests[2].last["Content-Type"], requests[2].last.body ]

    reply = JSON.parse(requests[3].last.body)["record"]
    assert_equal LINK.url, reply["text"]
    assert_equal({ "byteStart" => 0, "byteEnd" => LINK.url.bytesize }, reply.dig("facets", 0, "index"))
    assert_equal({ "uri" => "at://post", "cid" => "c1" }, reply.dig("reply", "parent"))
    assert_equal [ "寿限無", "落語", { "ref" => "b" } ], reply.dig("embed", "external").values_at("title", "description", "thumb")
  end

  test "本文の投稿が失敗したら理由を返し、返信だけの失敗は投稿の成功として理由を添える。理由に認証情報を入れない" do
    failed = client([ http(401, { error: "AuthenticationRequired", message: "Invalid identifier or password" }) ], []).publish(MESSAGE)
    assert_not failed.success?
    assert_equal "com.atproto.server.createSession: HTTP 401 AuthenticationRequired", failed.error

    timeout = client([ Net::OpenTimeout.new ], []).publish(MESSAGE)
    assert_equal "com.atproto.server.createSession: Net::OpenTimeout", timeout.error

    no_image = SnsPostText::Message.new(body: MESSAGE.body, link: LINK.with(image: nil))
    requests = []
    reply_failed = client([ session, http(200, { uri: "at://post", cid: "c1" }), http(500, {}) ], requests).publish(no_image)
    assert_equal BlueskyClient::Result.new(remote_id: "at://post", error: "返信: com.atproto.repo.createRecord: HTTP 500"), reply_failed
    assert_equal 3, requests.size, "画像が無ければ blob を上げない"
    assert_not_includes [ failed, timeout, reply_failed ].map(&:error).join, "secret-app-password"
  end
end
