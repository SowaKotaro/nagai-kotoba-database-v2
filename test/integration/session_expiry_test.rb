require "test_helper"

class SessionExpiryTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Admin.take
  end

  test "有効期限内のセッションは管理画面へアクセスできる" do
    sign_in_as(@admin)

    get admin_root_path

    assert_response :success
  end

  test "期限切れセッションはログイン画面へ誘導され、セッションレコードも破棄される" do
    sign_in_as(@admin)
    session = Current.session

    travel Session::LIFETIME + 1.day do
      get admin_root_path

      assert_redirected_to new_session_path
      assert_nil Session.find_by(id: session.id)
    end
  end

  test "期限内の利用で有効期限が延長される(スライディング)" do
    sign_in_as(@admin)
    session = Current.session
    original_updated_at = session.updated_at

    # 間引き間隔を超えてからのアクセスで最終利用時刻が進む
    travel Session::ACTIVITY_REFRESH_INTERVAL + 1.minute do
      get admin_root_path

      assert_response :success
      assert_operator session.reload.updated_at, :>, original_updated_at
    end

    # 当初ログインから LIFETIME 超の時点でも、延長済みなのでまだ使える
    # (延長が無ければ期限切れになっている時刻)
    travel Session::LIFETIME + 30.minutes do
      get admin_root_path

      assert_response :success
    end
  end

  test "ログイン時に期限切れセッションが掃除される" do
    stale_session = @admin.sessions.create!(updated_at: (Session::LIFETIME + 1.day).ago)

    post session_path, params: { username: @admin.username, password: "password" }

    assert_redirected_to root_path
    assert_nil Session.find_by(id: stale_session.id)
  end
end
