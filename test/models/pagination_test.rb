require "test_helper"

class PaginationTest < ActiveSupport::TestCase
  test "page_number は数字でない・0 以下の値を 1 ページ目にする" do
    assert_equal 1, Pagination.page_number(nil)
    assert_equal 1, Pagination.page_number("")
    assert_equal 1, Pagination.page_number("abc")
    assert_equal 1, Pagination.page_number("0")
    assert_equal 1, Pagination.page_number("-3")
    assert_equal 3, Pagination.page_number("3")
  end

  test "総ページ数は 0 件でも 1 で、端数は切り上げる" do
    assert_equal 1, Pagination.new(page: 1, per_page: 100, total_count: 0).total_pages
    assert_equal 1, Pagination.new(page: 1, per_page: 100, total_count: 100).total_pages
    assert_equal 2, Pagination.new(page: 1, per_page: 100, total_count: 101).total_pages
  end

  test "範囲はページ番号から offset を求めて limit と組にする" do
    pagination = Pagination.new(page: 3, per_page: 100, total_count: 1000)
    assert_equal 200, pagination.offset

    relation = pagination.paginate(Word.all)
    assert_equal 100, relation.limit_value
    assert_equal 200, relation.offset_value
  end
end
