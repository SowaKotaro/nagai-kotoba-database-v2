require "test_helper"

# 管理者のログイン・ログアウトと、セッションの有効期限(Issue 50)。
# 期限切れ・延長の判定そのものは SessionTest で見る。
class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @admin = Admin.take }

  test "正しい ID とパスワードでログインでき、そのとき期限切れのセッションを掃除する" do
    stale_session = @admin.sessions.create!(updated_at: (Session::LIFETIME + 1.day).ago)

    post session_path, params: { username: @admin.username, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_nil Session.find_by(id: stale_session.id)
  end

  test "パスワードが違えばログイン画面へ戻す" do
    post session_path, params: { username: @admin.username, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    follow_redirect!
    assert_response :success
  end

  test "ログアウトするとセッションを消してログイン画面へ戻す" do
    sign_in_as(@admin)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "期限切れのセッションはログイン画面へ誘導し、セッションレコードも破棄する" do
    sign_in_as(@admin)
    session = Current.session

    travel Session::LIFETIME + 1.day do
      get admin_root_path

      assert_redirected_to new_session_path
      assert_nil Session.find_by(id: session.id)
    end
  end

  test "期限内に使えば有効期限が延びる(スライディング)" do
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
end
