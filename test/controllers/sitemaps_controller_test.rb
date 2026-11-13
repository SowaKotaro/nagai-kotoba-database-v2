require "test_helper"

# sitemap.xml(Issue 15)。条件付きGET と版の畳み方は PublishedWordsDigestTest で見る。
class SitemapsControllerTest < ActionDispatch::IntegrationTest
  test "sitemap.xml は誰でも取得でき、静的ページと公開語の詳細だけを本番ホストの絶対URLで並べる" do
    get "/sitemap.xml"
    assert_response :success
    assert_match %r{application/xml|text/xml}, response.media_type
    assert_match "http://www.sitemaps.org/schemas/sitemap/0.9", response.body

    %w[/ /words /genres /entity_types /linguistic_features /browse /stats /about /privacy].each do |path|
      assert_includes response.body, "<loc>#{CANONICAL_HOST}#{path}</loc>"
    end
    assert_includes response.body, "<loc>#{CANONICAL_HOST}/words/#{words(:abc_murder).id}</loc>"
    assert_match %r{<lastmod>\d{4}-\d{2}-\d{2}}, response.body
    # 未注釈の語は含めない
    assert_not_includes response.body, "/words/#{words(:pending_haruhi).id}<"

    # sitemap.xml の <loc> は、静的ページ 10 件と公開語の詳細だけ(この順)
    get "/sitemap.xml"
    locs = Nokogiri::XML(response.body).remove_namespaces!.css("url > loc").map(&:text)

    static = %w[/ /words /genres /entity_types /linguistic_features /browse /rankings /stats /about /privacy]
             .map { |path| "#{CANONICAL_HOST}#{path}" }
    published = Word.annotated.order(:id).map { |word| "#{CANONICAL_HOST}/words/#{word.id}" }
    assert_equal static + published, locs
  end

  # ファセット面のサイトマップ(docs/seo-plan.md §5 C-2)。どの面を載せるかの規則は IndexableFacetsTest で見る。
  test "sitemap-facets.xml は、インデックスさせる単一条件の一覧だけを canonical と同じ URL で並べる" do
    genre = genres(:small_novel)
    IndexableFacets::SITEMAP_MIN_COUNT.times do |i|
      create_published_word(surface: "面に載る語#{i}", reading: "ツチノコハッケンタイ#{%w[ア イ ウ][i]}", genre: genre)
    end
    create_published_word(surface: "薄い面の語", reading: "ヌ" * 31)

    get "/sitemap-facets.xml"
    assert_response :success
    assert_match %r{application/xml|text/xml}, response.media_type
    xml = Nokogiri::XML(response.body).remove_namespaces!
    locs = xml.css("url > loc").map(&:text)

    expected = IndexableFacets.for_sitemap.map { |facet| "#{CANONICAL_HOST}#{words_path(facet.key => facet.value)}" }
    assert_equal expected, locs
    assert_includes locs, "#{CANONICAL_HOST}/words?first_char=%E3%83%84"
    assert_includes locs, "#{CANONICAL_HOST}/words?genre_id=#{genre.id}"
    assert_includes locs, "#{CANONICAL_HOST}/words?reading_length=11"
    # 語義が下限に届かない面は載せない(インデックスの可否は変えない)
    assert_not_includes locs, "#{CANONICAL_HOST}/words?reading_length=31"
    # 面の更新日時は正確に出せないので lastmod を付けない。条件の組み合わせ・並び替え・ページ送り・単語詳細も載せない
    assert_empty xml.css("lastmod")
    assert locs.all? { |loc| loc.match?(%r{\A#{Regexp.escape(CANONICAL_HOST)}/words\?[a-z_]+=[^&]+\z}) }

    # 載せた URL はどれも、開くとインデックス可(noindex なし)で、canonical が自身を指す
    # (サイトマップとページの宣言が食い違うと、Google はサイトマップの側を信用しなくなる)
    locs.each do |loc|
      get loc.delete_prefix(CANONICAL_HOST)
      assert_response :success, "#{loc} が開けない"
      assert_select "meta[name=robots]", { count: 0 }, "#{loc} が noindex になっている"
      assert_select "link[rel=canonical][href=?]", loc
    end
  end
end
