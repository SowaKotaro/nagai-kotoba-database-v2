require "test_helper"

# インデックス解禁スイッチ(Issue 43)の結合テスト。
# テスト環境の既定は「解禁後」(config/environments/test.rb)。
# 解禁前(未設定 = 全ページ noindex)の挙動はこのテストが明示的に切り替えて検証する。
class IndexingSwitchTest < ActionDispatch::IntegrationTest
  test "解禁前は全ページに noindex が出る(個別指定より優先)" do
    with_indexing_disabled do
      # 通常は robots メタを出さないページ
      [ root_path, words_path, word_path(words(:abc_murder)), about_path ].each do |path|
        get path
        assert_select "meta[name=robots][content=?]", "noindex", true,
                      "#{path} が解禁前なのに noindex ではない"
      end

      # ページ個別に noindex,follow を指定するページも全体の noindex が優先される
      get search_path
      assert_select "meta[name=robots][content=?]", "noindex"
      assert_select "meta[name=robots]", count: 1
    end
  end

  test "解禁後は通常ページに robots メタを出さずページ個別の指定に従う" do
    get root_path
    assert_select "meta[name=robots]", count: 0

    get search_path
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  private

  # 解禁前(INDEXING_ENABLED 未設定)の状態を一時的に再現する。
  def with_indexing_disabled
    Rails.application.config.x.indexing_enabled = false
    yield
  ensure
    Rails.application.config.x.indexing_enabled = true
  end
end
