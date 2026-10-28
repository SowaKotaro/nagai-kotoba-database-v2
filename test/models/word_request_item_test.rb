require "test_helper"

# 収録リクエストの1語(Issue 75)。正規化・要注意フラグ・状態の記録。
class WordRequestItemTest < ActiveSupport::TestCase
  def build_item(attributes = {})
    WordRequest.new(ip_address: "203.0.113.9").items.build({ surface: "リクエストの言葉" }.merge(attributes))
  end

  test "表層形は改行を空白に畳んで前後を落とし、必須で長さに上限がある(短い読みは受け付ける)" do
    item = build_item(surface: "  改行の入った\n言葉  ")
    item.valid?

    assert_equal "改行の入った 言葉", item.surface

    # 語の一部としてのスペースは残す
    item = build_item(surface: "Dead by Daylight")
    item.valid?

    assert_equal "Dead by Daylight", item.surface

    # 表層形が空なら保存できない
    assert_not build_item(surface: " ").valid?

    # 長すぎる入力は受け付けない
    assert_not build_item(surface: "あ" * (WordRequestItem::MAX_SURFACE_LENGTH + 1)).valid?
    assert_not build_item(reading: "ア" * (WordRequestItem::MAX_READING_LENGTH + 1)).valid?
    assert_not build_item(admin_memo: "め" * (WordRequestItem::MAX_ADMIN_MEMO_LENGTH + 1)).valid?

    # 上限ちょうどは受け付ける
    assert build_item(surface: "あ" * WordRequestItem::MAX_SURFACE_LENGTH,
                      reading: "ア" * WordRequestItem::MAX_READING_LENGTH,
                      admin_memo: "め" * WordRequestItem::MAX_ADMIN_MEMO_LENGTH).valid?

    # 収録基準を満たさない短い読みでも受け付ける
    # 入口で弾くと読みの書き間違いで正当な語まで落ちるため、選別は管理側で行う。
    item = build_item(reading: "ミジカイ")

    assert_operator item.reading.length, :<, WordSense::MIN_READING_LENGTH
    assert_predicate item, :valid?
  end

  test "状態を動かすと処理時刻が入り、未着手へ戻すと消える" do
    item = build_item
    item.save!

    assert_predicate item, :pending?
    assert_nil item.handled_at

    # 状態を動かすと処理時刻が入る
    item = build_item
    item.save!

    item.update!(status: :accepted)
    assert_predicate item.handled_at, :present?

    # 未着手へ戻すと処理時刻を消す
    item = build_item
    item.save!
    item.update!(status: :rejected)

    item.update!(status: :pending)
    assert_nil item.handled_at
  end
end
