require "test_helper"

# 新着単語の Atom フィード(Issue 28)の結合テスト。
class WordsFeedTest < ActionDispatch::IntegrationTest
  test "words.atom は注釈済みの語を公開日の新しい順に FEED_LIMIT 件まで載せ、レイアウトから案内する" do
    get words_path(format: :atom)
    assert_response :success
    assert_equal "application/atom+xml", response.media_type

    feed = Nokogiri::XML(response.body)
    feed.remove_namespaces!
    titles = feed.css("entry > title").map(&:text)
    assert_includes titles, words(:abc_murder).surface
    assert_includes titles, words(:curry).surface
    assert_not_includes titles, words(:pending_haruhi).surface # 未注釈は出さない
    # curry(6/2)が abc_murder(6/1)より先
    assert_operator titles.index(words(:curry).surface), :<, titles.index(words(:abc_murder).surface)
    # エントリ本文はリード文(「日本語の長い言葉」を含む)
    assert(feed.css("entry > content").any? { |c| c.text.include?("日本語の長い言葉") })

    # words.atom は FEED_LIMIT 件までで、一覧の絞り込みを無視し、エントリの URL は本番ホスト
    (WordsController::FEED_LIMIT - 1).times do |index|
      create_annotated_word_with_genre(surface: "フィードの件数上限の見本その#{index}",
                                       reading: "フィードノケンスウジョウゲンノミホンソノ#{index}", genre: genres(:small_novel))
    end
    assert_operator Word.annotated.count, :>, WordsController::FEED_LIMIT

    get words_path(format: :atom)
    feed = Nokogiri::XML(response.body).remove_namespaces!
    titles = feed.css("entry > title").map(&:text)
    assert_equal WordsController::FEED_LIMIT, titles.size
    assert(feed.css("entry > link").all? { |link| link["href"].start_with?("#{CANONICAL_HOST}/words/") })

    get words_path(format: :atom, first_char: word_senses(:curry).first_char)
    assert_equal titles, Nokogiri::XML(response.body).remove_namespaces!.css("entry > title").map(&:text)

    # レイアウトに Atom の autodiscovery link がある
    get root_path
    assert_select "link[rel=alternate][type='application/atom+xml'][href=?]", "/words.atom"
  end

  test "条件付きGET で 304 を返し、ジャンル名の変更(touch されないマスタ)では作り直す" do
    get words_path(format: :atom)
    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get words_path(format: :atom), headers: { "If-None-Match" => etag }
    assert_response :not_modified

    genres(:medium_japanese).update!(name: "日本文学(改名)")

    get words_path(format: :atom), headers: { "If-None-Match" => etag }
    assert_response :success
  end

  private

  # ジャンル(小分類)付きの注釈済み語を1語作る。
  def create_annotated_word_with_genre(surface:, reading:, genre:)
    word = Word.new(surface: surface)
    word.word_senses.build(reading: reading, genre: genre)
    word.mark_annotated
    word.save!
    word
  end
end
