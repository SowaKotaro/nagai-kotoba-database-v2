require "test_helper"

# 収録リクエストの1語(Issue 75)。正規化・要注意フラグ・状態の記録。
class WordRequestItemTest < ActiveSupport::TestCase
  def build_item(attributes = {})
    WordRequest.new(ip_address: "203.0.113.9").items.build({ surface: "リクエストの言葉" }.merge(attributes))
  end

  test "表層形の改行は空白に畳んで前後を落とす" do
    item = build_item(surface: "  改行の入った\n言葉  ")
    item.valid?

    assert_equal "改行の入った 言葉", item.surface
  end

  test "語の一部としてのスペースは残す" do
    item = build_item(surface: "Dead by Daylight")
    item.valid?

    assert_equal "Dead by Daylight", item.surface
  end

  test "既定の状態は未着手で、処理時刻は入らない" do
    item = build_item
    item.save!

    assert_predicate item, :pending?
    assert_nil item.handled_at
  end

  test "状態を動かすと処理時刻が入る" do
    item = build_item
    item.save!

    item.update!(status: :accepted)
    assert_predicate item.handled_at, :present?
  end

  test "未着手へ戻すと処理時刻を消す" do
    item = build_item
    item.save!
    item.update!(status: :rejected)

    item.update!(status: :pending)
    assert_nil item.handled_at
  end

  test "表層形が空なら保存できない" do
    assert_not build_item(surface: " ").valid?
  end

  test "長すぎる入力は受け付けない" do
    assert_not build_item(surface: "あ" * (WordRequestItem::MAX_SURFACE_LENGTH + 1)).valid?
    assert_not build_item(reading: "ア" * (WordRequestItem::MAX_READING_LENGTH + 1)).valid?
    assert_not build_item(admin_memo: "め" * (WordRequestItem::MAX_ADMIN_MEMO_LENGTH + 1)).valid?
  end

  test "上限ちょうどは受け付ける" do
    assert build_item(surface: "あ" * WordRequestItem::MAX_SURFACE_LENGTH,
                      reading: "ア" * WordRequestItem::MAX_READING_LENGTH,
                      admin_memo: "め" * WordRequestItem::MAX_ADMIN_MEMO_LENGTH).valid?
  end

  test "収録基準を満たさない短い読みでも受け付ける" do
    # 入口で弾くと読みの書き間違いで正当な語まで落ちるため、選別は管理側で行う。
    item = build_item(reading: "ミジカイ")

    assert_operator item.reading.length, :<, WordSense::MIN_READING_LENGTH
    assert_predicate item, :valid?
  end
end
