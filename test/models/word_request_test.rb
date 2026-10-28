require "test_helper"

# 収録リクエスト1通(Issue 75)。語数の上限と、保存済みレコードで数えるレートリミット。
class WordRequestTest < ActiveSupport::TestCase
  IP = "203.0.113.9".freeze

  def build_request(ip: IP, items: { "0" => { surface: "リクエストの言葉" } })
    WordRequest.new(ip_address: ip, items_attributes: items)
  end

  test "言葉と IP が要り、空行は捨て、語数は上限まで" do
    request = WordRequest.new(ip_address: IP)
    assert_not request.valid?

    # IP が無ければ保存できない
    assert_not build_request(ip: nil).valid?

    # すべて空の行は捨てる
    request = build_request(items: {
      "0" => { surface: "ちゃんとした言葉", reading: "" },
      "1" => { surface: "", reading: "" }
    })
    assert request.valid?
    assert_equal 1, request.items.size

    # 空行しか無ければ保存できない
    assert_not build_request(items: { "0" => { surface: "", reading: "" } }).valid?

    # 上限までの語数は受け付ける
    items = (1..WordRequest::MAX_ITEMS).index_with { |i| { surface: "言葉#{i}" } }.transform_keys(&:to_s)
    assert build_request(items: items).valid?

    # 上限を超える語数は受け付けない
    items = (0..WordRequest::MAX_ITEMS).index_with { |i| { surface: "言葉#{i}" } }.transform_keys(&:to_s)
    request = build_request(items: items)

    assert_not request.valid?
    assert_includes request.errors.full_messages.join, WordRequest::MAX_ITEMS.to_s
  end

  test "同じ IP から短時間に送りすぎたら制限にかかる" do
    limit = WordRequest::RATE_LIMITS.first.last

    (limit - 1).times { build_request.save! }
    assert_not WordRequest.rate_limited?(IP)

    build_request.save!
    assert WordRequest.rate_limited?(IP)
  end

  test "レートリミットは期間を過ぎた送信と、別の IP・空の IP の送信を数えない" do
    period, limit = WordRequest::RATE_LIMITS.first

    travel_to((period + 1.minute).ago) do
      limit.times { build_request.save! }
    end
    assert_not WordRequest.rate_limited?(IP)

    # 別の IP の送信は影響しない
    WordRequest::RATE_LIMITS.first.last.times { build_request.save! }

    assert_not WordRequest.rate_limited?("198.51.100.1")

    # IP が空なら制限の対象にしない
    assert_not WordRequest.rate_limited?(nil)
    assert_not WordRequest.rate_limited?("")
  end
end
