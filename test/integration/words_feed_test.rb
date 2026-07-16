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

  test "ジャンル祖先を preload し genres へのクエリが語数に比例しない(N+1 回帰)" do
    # 別系統のジャンルを持つ注釈済み語を増やす。既存フィクスチャと同じジャンルだと
    # preload が同一インスタンスを共有し parent の遅延ロードが1回で済んでしまうため、
    # 独立した 大→中→小 を新設して「語(系統)ごとに parent を辿る」形の N+1 を顕在化させる。
    create_annotated_word_with_genre(surface: "残業手当不払い請求事件", reading: "ザンギョウテアテフバライセイキュウジケン",
                                     genre: create_small_genre_tree)

    genre_query_count = count_queries(/FROM\s+`genres`/i) { get words_path(format: :atom) }
    assert_response :success
    # preload なら階層ごとの3クエリ(小・中・大)で頭打ちになる。
    # genre 止まりの preload だと系統ごとに 中→大 の2クエリが上乗せされる(この時点で5)
    assert_operator genre_query_count, :<=, 3
  end

  test "条件付きGET(If-None-Match)で 304 を返す" do
    get words_path(format: :atom)
    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get words_path(format: :atom), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "ジャンル名の変更(touch されないマスタ)でも ETag が変わる" do
    get words_path(format: :atom)
    etag = response.headers["ETag"]

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

  # フィクスチャと独立した 大→中→小 のジャンル系統を作り、小分類を返す。
  def create_small_genre_tree
    large = Genre.create!(level: :large, name: "法律")
    medium = Genre.create!(level: :medium, name: "労働法", parent: large)
    Genre.create!(level: :small, name: "判例", parent: medium)
  end

  # ブロック実行中に発行された SQL のうち pattern に一致する件数を数える。
  def count_queries(pattern)
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].match?(pattern)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
