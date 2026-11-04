require "test_helper"

class RankingsHelperTest < ActionView::TestCase
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
