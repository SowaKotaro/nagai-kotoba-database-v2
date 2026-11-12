require "test_helper"

class ResearchDuplicateFilterTest < ActiveSupport::TestCase
  test "表層形は畳んで完全一致、読みは Levenshtein のしきい値以上を重複とし、通した語を以降の相手に足す" do
    filter = ResearchDuplicateFilter.new([ [ "ゴールドマン・サックス", "ゴールドマンサックス" ], [ "読みの無い語", nil ] ])

    # 中黒・かなの種類の違いは同じ語とみなす
    match = filter.match("ごーるどまんさっくす", nil)
    assert_equal [ :surface, "ゴールドマン・サックス" ], [ match.kind, match.surface ]
    # 読みが似ていれば(兄弟の語でも)重複
    match = filter.match("ファイナルファンタジーセブン", "ゴールドマンサックス")
    assert_equal [ :reading, "ゴールドマン・サックス", "ゴールドマンサックス" ], [ match.kind, match.surface, match.reading ]
    # 似ていない語・読みが空の語は通る
    assert_nil filter.match("ファイナルファンタジーセブン", "ファイナルファンタジーセブン")
    assert_nil filter.match("別の語", nil)

    # 通した語は、同じ run の後ろの語の相手になる(先に来た語を正とする)
    filter.remember("ファイナルファンタジーセブン", "ファイナルファンタジーセブン")
    assert_equal :reading, filter.match("ファイナルファンタジーテン", "ファイナルファンタジーテン").kind
  end
end
