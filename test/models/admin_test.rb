require "test_helper"

class AdminTest < ActiveSupport::TestCase
  test "username は前後の空白を落として小文字に揃える" do
    admin = Admin.new(username: " DOWNCASED_ADMIN ")
    assert_equal("downcased_admin", admin.username)
  end
end
