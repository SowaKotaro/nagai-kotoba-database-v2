require "test_helper"

class GenresHelperTest < ActionView::TestCase
  test "公開件数: 小分類は集計値、上位は子孫の合計" do
    large  = Genre.new(id: 1)
    medium = Genre.new(id: 2)
    small_a = Genre.new(id: 3)
    small_b = Genre.new(id: 4)
    by_parent = { nil => [ large ], 1 => [ medium ], 2 => [ small_a, small_b ] }
    counts = { 3 => 5, 4 => 2 }

    assert_equal 5, genre_published_count(small_a, by_parent, counts)
    assert_equal 7, genre_published_count(medium, by_parent, counts)
    assert_equal 7, genre_published_count(large, by_parent, counts)
  end

  test "公開語義が0の分類は除外される" do
    large   = Genre.new(id: 1)
    m_full  = Genre.new(id: 2)
    m_empty = Genre.new(id: 5)
    small   = Genre.new(id: 3)
    s_empty = Genre.new(id: 6)
    by_parent = { nil => [ large ], 1 => [ m_full, m_empty ], 2 => [ small ], 5 => [ s_empty ] }
    counts = { 3 => 4 } # id 6 は0件

    assert_equal [ m_full ], genres_with_published(1, by_parent, counts)
    assert_equal [ small ], genres_with_published(2, by_parent, counts)
    assert_empty genres_with_published(5, by_parent, counts)
  end
end
