module RankingsHelper
  # 畳みきれなかった語(WordRanking::FOLD_LIMIT を超えたぶん)の続き。同じ並びの単語一覧のうち、
  # その組が始まるページへ渡す(下の順位の組は一覧の 2 ページ目以降から始まる)。1 ページ目は page を付けない。
  def rank_fold_rest_path(ranking, group)
    page = group[:offset] / WordsController::PER_PAGE + 1
    words_path(sort: ranking.key, page: (page if page > 1))
  end
end
