require "test_helper"

class SnsBroadcastTest < ActiveSupport::TestCase
  # 送った文面を覚え、決めた結果を返すクライアント。
  class FakeClient
    attr_reader :messages

    def initialize(*results)
      @results = results
      @messages = []
    end

    def publish(message)
      @messages << message
      @results.shift
    end
  end

  NOW = Time.zone.local(2026, 11, 18, 9, 41)

  def ok(id) = SnsClient::Result.new(remote_id: id, error: nil)
  def ng(error) = SnsClient::Result.new(remote_id: nil, error:)

  test "同じ時刻には SNS ごとに 1 回だけ送り、1 つが落ちてもほかへは送り、失敗した SNS だけを送り直す" do
    bluesky = FakeClient.new(ok("at://1"))
    threads = FakeClient.new(ng("HTTP 500"), ok("t-1"))
    clients = { bluesky:, threads: }

    result = SnsBroadcast.new(clients:, now: NOW).call
    assert_equal({ bluesky: :posted, threads: :failed }, result.outcomes)
    assert result.failed?
    slot = result.slot
    assert_equal [ Time.zone.local(2026, 11, 18, 9), 1 ], [ slot.slot_at, slot.round ]
    assert_equal slot.word.surface, bluesky.messages.first.body.lines.first.chomp
    assert_equal({ "bluesky" => [ "posted", "at://1", nil ], "threads" => [ "failed", nil, "HTTP 500" ] },
                 slot.sns_posts.to_h { [ it.platform, [ it.status, it.remote_id, it.error_message ] ] })

    # 同じ時刻にもう一度: 失敗した Threads だけ、同じ語で送り直す
    retried = SnsBroadcast.new(clients:, now: NOW + 10.minutes).call
    assert_equal({ bluesky: :skipped, threads: :posted }, retried.outcomes)
    assert_equal slot, retried.slot
    assert_equal [ 1, 2 ], [ bluesky.messages.size, threads.messages.size ]
    assert_equal threads.messages.first, threads.messages.last

    # 次の時刻は別の枠で、別の語
    next_hour = SnsBroadcast.new(clients: { bluesky: FakeClient.new(ok("at://2")) }, now: NOW + 1.hour).call
    assert_not_equal slot.word, next_hour.slot.word
  end

  test "語を指定すると、まだ無い枠をその語で作り、その巡ではもう選ばない。本文が収まらない語は断る" do
    client = FakeClient.new(ok("at://1"), ok("at://2"))
    first = SnsBroadcast.new(clients: { bluesky: client }, now: NOW, word_id: words(:curry).id).call
    assert_equal [ words(:curry), 1 ], [ first.slot.word, first.slot.round ]

    second = SnsBroadcast.new(clients: { bluesky: client }, now: NOW + 1.hour).call
    assert_equal [ words(:abc_murder), 1 ], [ second.slot.word, second.slot.round ]

    long = create_published_word(surface: "長" * 70, reading: "ナ" * 70)
    assert_raises(ArgumentError) { SnsBroadcast.new(clients: { bluesky: client }, now: NOW + 2.hours, word_id: long.id).call }
  end

  test "送り先が無いとき・枠の語が非公開に戻ったときは送らない" do
    assert_nil SnsBroadcast.new(clients: {}, now: NOW).call.slot
    assert_not SnsSlot.exists?

    client = FakeClient.new(ok("at://1"))
    SnsSlot.create!(slot_at: NOW.beginning_of_hour, word: words(:curry), round: 1)
    words(:curry).mark_on_hold
    words(:curry).save!

    assert_nil SnsBroadcast.new(clients: { bluesky: client }, now: NOW).call.slot
    assert_empty client.messages
  end
end
