require "test_helper"

class SiteUrlTest < ActiveSupport::TestCase
  test "起点はスキーム付き、host は裸のホストで、absolute はパスに起点を前置する" do
    assert_equal CANONICAL_HOST, SiteUrl.origin
    assert_equal "nagai-kotoba-database.jp", SiteUrl.host
    assert_equal "#{CANONICAL_HOST}/words/1", SiteUrl.absolute("/words/1")
    assert_equal "#{CANONICAL_HOST}#{SiteUrl::DEFAULT_OG_IMAGE_PATH}", SiteUrl.absolute(SiteUrl::DEFAULT_OG_IMAGE_PATH)
  end

  test "起点は設定(config.x.canonical_host)に連動する" do
    with_config(canonical_host: "https://example.test") do
      assert_equal "https://example.test/about", SiteUrl.absolute("/about")
      assert_equal "example.test", SiteUrl.host
    end
  end
end
