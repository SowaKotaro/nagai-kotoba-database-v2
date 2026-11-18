require "test_helper"

# X には送らず、送るはずだった要求を記録して、決めた応答を返す。
class XClientTest < ActiveSupport::TestCase
  MESSAGE = SnsPostText::Message.new(
    body: "寿限無\nジュゲム（4文字）",
    link: SnsPostText::Link.new(url: "https://nagai-kotoba-database.jp/words/1", title: "寿限無", description: "落語", image: "PNG")
  )
  KEYS = { api_key: "consumer-key", api_key_secret: "consumer-secret", access_token: "token", access_token_secret: "token-secret" }.freeze

  def http(status, body)
    Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s).new("1.1", status.to_s, "").tap do |response|
      response.instance_variable_set(:@body, body.to_json)
      response.instance_variable_set(:@read, true)
    end
  end

  def client(response, requests = [])
    XClient.new(**KEYS, transport: ->(uri, request) { requests << [ uri, request ]; response.is_a?(Exception) ? raise(response) : response })
  end

  test "OAuth 1.0a の署名は X の文書の例と一致する" do
    params = {
      include_entities: "true", status: "Hello Ladies + Gentlemen, a signed OAuth request!",
      oauth_consumer_key: "xvz1evFS4wEEPTGEFPHBog", oauth_nonce: "kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg",
      oauth_signature_method: "HMAC-SHA1", oauth_timestamp: "1318622958",
      oauth_token: "370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb", oauth_version: "1.0"
    }
    assert_equal "hCtSmYh+iHYCEqBWrE7C7hYmtUk=",
                 XClient.signature("post", "https://api.twitter.com/1.1/statuses/update.json", params,
                                   consumer_secret: "kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw",
                                   token_secret: "LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE")
  end

  test "本文だけを JSON で投稿し、リンクは付けない。署名つきの OAuth の見出しを付ける" do
    requests = []
    result = client(http(201, { data: { id: "1990", text: MESSAGE.body } }), requests).publish(MESSAGE)

    assert_equal SnsClient::Result.new(remote_id: "1990", error: nil), result
    uri, request = requests.sole
    assert_equal "https://api.x.com/2/tweets", uri.to_s
    assert_equal({ "text" => MESSAGE.body }, JSON.parse(request.body))
    header = request["Authorization"]
    assert_match(/\AOAuth /, header)
    assert_includes header, 'oauth_consumer_key="consumer-key"'
    assert_includes header, 'oauth_token="token"'
    assert_match(/oauth_signature="[^"]+"/, header)
    assert_not_includes header, "secret"
  end

  test "失敗は理由を返し、理由に鍵を入れない。鍵が 1 つでも欠ければクライアントを作らない" do
    no_credit = client(http(402, { title: "CreditsDepleted", detail: "consumer-secret" })).publish(MESSAGE)
    assert_equal SnsClient::Result.new(remote_id: nil, error: "HTTP 402 CreditsDepleted"), no_credit
    assert_equal "Net::ReadTimeout", client(Net::ReadTimeout.new).publish(MESSAGE).error

    settings = KEYS.transform_keys { :"sns_x_#{it}" }
    with_config(**settings) { assert_kind_of XClient, XClient.from_config }
    with_config(**settings, sns_x_access_token_secret: "") { assert_nil XClient.from_config }
  end
end
