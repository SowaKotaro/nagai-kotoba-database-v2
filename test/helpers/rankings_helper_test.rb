require "test_helper"

class RankingsHelperTest < ActionView::TestCase
  test "説明文の頭には読みが長い言葉の 1 位を置き、板が無いときと語が長すぎるときは、もとの説明文のままにする" do
    base = I18n.t("rankings.index.description")
    length_board = WordRanking.all.find { |ranking| ranking.key == RankingsHelper::META_TOP_KEY }
    other_board = WordRanking.all.find { |ranking| ranking.key == "mora_desc" }
    boards = ->(surface, count) { [ [ other_board, [] ], [ length_board, [ { value: 1234, count: count, representative: { surface: surface } } ] ] ] }

    assert_equal "読みがいちばん長い言葉は「長い語」（1,234字）。#{base}", rankings_meta_description(boards.("長い語", 1))
    # 同じ長さの語が複数あれば、代表の語と語数を言う
    assert_equal "読みがいちばん長い言葉は「長い語」など3語（1,234字）。#{base}", rankings_meta_description(boards.("長い語", 3))
    # 説明文は約 120 字で切られるので、長すぎる語は名指ししない(上限ちょうどまでは名指しする)
    limit = RankingsHelper::META_TOP_SURFACE_MAX_LENGTH
    assert_includes rankings_meta_description(boards.("長" * limit, 1)), "長" * limit
    assert_equal base, rankings_meta_description(boards.("長" * (limit + 1), 1))
    # その板が成立していない(出ていない)とき
    assert_equal base, rankings_meta_description([ [ other_board, [] ] ])
    assert_equal base, rankings_meta_description([])
  end

  test "畳みきれなかった語の続きは、同じ並びの単語一覧のうち組が始まるページへ渡す" do
    ranking = WordRanking.all.find { |candidate| candidate.key == "chouon_desc" }
    per_page = WordsController::PER_PAGE

    # 1 ページ目は page を付けない(もっと見ると同じ URL)
    assert_equal words_path(sort: "chouon_desc"), rank_fold_rest_path(ranking, { offset: 0 })
    assert_equal words_path(sort: "chouon_desc"), rank_fold_rest_path(ranking, { offset: per_page - 1 })
    # 上の組の語数がちょうど 1 ページぶんなら、組は 2 ページ目の先頭から始まる
    assert_equal words_path(sort: "chouon_desc", page: 2), rank_fold_rest_path(ranking, { offset: per_page })
    assert_equal words_path(sort: "chouon_desc", page: 4), rank_fold_rest_path(ranking, { offset: per_page * 3 + 1 })
  end
end
