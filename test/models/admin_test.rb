require "test_helper"

class AdminTest < ActiveSupport::TestCase
  test "downcases and strips username" do
    admin = Admin.new(username: " DOWNCASED_ADMIN ")
    assert_equal("downcased_admin", admin.username)
  end
end
