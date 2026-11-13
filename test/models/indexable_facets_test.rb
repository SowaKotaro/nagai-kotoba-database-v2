require "test_helper"

# インデックスを許可しているファセット面の列挙(ファセット面のサイトマップの中身。docs/seo-plan.md §5 C-2)。
class IndexableFacetsTest < ActiveSupport::TestCase
  test "インデックスを許可した条件の、公開語義のある値だけを、その面の一覧と同じ件数で並べる" do
    # 件数の出どころは、ジャンル(上位の分類へ合算する)を除く許可済みの条件のすべてに決めてある
    # (WordSenseSearch::INDEXABLE_FACET_KEYS に条件を足したら、ここで分かる)
    assert_equal WordSenseSearch::INDEXABLE_FACET_KEYS - [ :genre_id ], IndexableFacets::COUNT_SOURCES.keys

    small = genres(:small_novel)
    3.times { |i| create_published_word(surface: "列挙の語#{i}", reading: "ナニヌネノハヒフヘホマミ#{%w[ム メ モ][i]}", genre: small) }
    # 50音表に無い字で始まる読みと、未公開の語は面にしない
    create_published_word(surface: "英字で始まる語", reading: "Xアイウエオカキクケコ")

    facets = IndexableFacets.all
    assert_equal WordSenseSearch::INDEXABLE_FACET_KEYS, facets.map(&:key).uniq, "面の種類の順が許可済みの条件の順と違う"
    assert facets.all? { |facet| facet.count.positive? }
    assert_equal facets.map { |facet| [ facet.key, facet.value ] }.uniq.size, facets.size

    # 件数は、その面の一覧(単語一覧の絞り込み)が返す公開語義の数と同じ。ジャンルは小・中・大のどれも面になる
    facets.each do |facet|
      listed = WordSenseSearch.new(facet.key => facet.value).results.distinct.count(:id)
      assert_equal listed, facet.count, "#{facet.key}=#{facet.value} の件数が一覧と違う"
    end
    genre_counts = facets.select { |facet| facet.key == :genre_id }.to_h { |facet| [ facet.value, facet.count ] }
    [ small, small.parent, small.parent.parent ].each { |genre| assert_operator genre_counts[genre.id], :>=, 3 }

    values = ->(key) { facets.select { |facet| facet.key == key }.map(&:value) }
    assert_includes values.call(:first_char), "ナ"
    assert_not_includes values.call(:first_char), "X"
    assert_includes values.call(:reading_length), 13
    # 未公開の語(フィクスチャの 涼宮ハルヒの憂鬱)だけが持つ文字数
    assert_not_includes values.call(:reading_length), words(:pending_haruhi).word_senses.first.reading_length
    assert_equal values.call(:reading_length).sort, values.call(:reading_length)
  end

  test "サイトマップに載せるのは、公開語義が下限以上の面だけ" do
    create_published_word(surface: "薄い面の語", reading: "ア" * 31)
    IndexableFacets::SITEMAP_MIN_COUNT.times { |i| create_published_word(surface: "厚い面の語#{i}", reading: "イ" * 32) }

    lengths = ->(facets) { facets.select { |facet| facet.key == :reading_length }.map(&:value) }
    assert_includes lengths.call(IndexableFacets.all), 31
    assert_not_includes lengths.call(IndexableFacets.for_sitemap), 31
    assert_includes lengths.call(IndexableFacets.for_sitemap), 32
  end
end
