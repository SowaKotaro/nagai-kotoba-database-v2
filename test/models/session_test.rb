require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup do
    @admin = admins(:one)
  end

  test "無操作が LIFETIME を超えたら失効する(ちょうど手前は失効しない)" do
    session = @admin.sessions.create!

    assert_not session.expired?
    assert_not_includes Session.expired, session

    # 無操作が LIFETIME を超えたセッションは失効する
    session = @admin.sessions.create!

    travel Session::LIFETIME + 1.minute do
      assert_predicate session, :expired?
      assert_includes Session.expired, session
    end

    # LIFETIME ちょうど手前では失効しない(境界値)
    session = @admin.sessions.create!

    travel Session::LIFETIME - 1.minute do
      assert_not session.expired?
    end
  end

  test "refresh_activity は間引き間隔を超えたときだけ updated_at を更新する" do
    session = @admin.sessions.create!
    original_updated_at = session.updated_at

    travel Session::ACTIVITY_REFRESH_INTERVAL - 1.minute do
      assert_nil session.refresh_activity
      assert_equal original_updated_at, session.reload.updated_at
    end

    # refresh_activity は間引き間隔を超えていれば updated_at を更新する
    session = @admin.sessions.create!
    original_updated_at = session.updated_at

    travel Session::ACTIVITY_REFRESH_INTERVAL + 1.minute do
      assert session.refresh_activity
      assert_operator session.reload.updated_at, :>, original_updated_at
    end
  end
end
