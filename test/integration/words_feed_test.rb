require "test_helper"

# 新着単語の Atom フィード(Issue 28)の結合テスト。
class WordsFeedTest < ActionDispatch::IntegrationTest
  test "words.atom は Atom フィードを返し新着の注釈済み語を含む" do
    get words_path(format: :atom)
    assert_response :success
    assert_equal "application/atom+xml", response.media_type

    feed = Nokogiri::XML(response.body)
    feed.remove_namespaces!
    titles = feed.css("entry > title").map(&:text)
    assert_includes titles, words(:abc_murder).surface
    assert_includes titles, words(:curry).surface
    # 未注釈は出さない
    assert_not_includes titles, words(:pending_haruhi).surface
    # エントリ本文はリード文(「日本語の長い言葉」を含む)
    assert(feed.css("entry > content").any? { |c| c.text.include?("日本語の長い言葉") })
  end

  test "新着順(annotated_at 降順)で並ぶ" do
    get words_path(format: :atom)
    feed = Nokogiri::XML(response.body)
    feed.remove_namespaces!
    titles = feed.css("entry > title").map(&:text)
    # curry(6/2)が abc_murder(6/1)より先
    assert_operator titles.index(words(:curry).surface), :<, titles.index(words(:abc_murder).surface)
  end

  test "レイアウトに Atom の autodiscovery link がある" do
    get root_path
    assert_select "link[rel=alternate][type='application/atom+xml'][href=?]", "/words.atom"
  end
end
