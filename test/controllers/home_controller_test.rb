require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "未認証でもトップページを閲覧できる" do
    get root_path
    assert_response :success
  end
end
