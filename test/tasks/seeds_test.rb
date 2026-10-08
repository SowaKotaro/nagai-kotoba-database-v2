require "test_helper"

# db/seeds.rb はデプロイのたびに流れ(config/deploy.rb の deploy:seed)、出力はデプロイのログに残る。
# リポジトリが公開なので、そのログは誰でも読める。
class SeedsTest < ActiveSupport::TestCase
  test "管理者を作っても、出力にログイン ID を出さない" do
    username = "seed-test-admin"
    output, = with_env("ADMIN_USERNAME" => username, "ADMIN_PASSWORD" => "seed-test-password") do
      capture_io { load Rails.root.join("db/seeds.rb") }
    end

    assert Admin.exists?(username: username)
    assert_includes output, "管理者を作成/更新しました"
    assert_not_includes output, username
  end
end
