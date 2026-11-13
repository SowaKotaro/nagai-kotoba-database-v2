module RankingsHelper
  # meta description の頭で 1 位の値を言う順位表(このサイトの看板の数)。
  META_TOP_KEY = "length_desc".freeze

  # /rankings の meta description。「読みが長い言葉」の 1 位の値(WordRanking#board が決めた組の値)を頭に置く。
  # 語は名指ししない(最長の語は表記も長く、約 120 字で切られる説明文が語だけで埋まる)。
  # boards はコントローラが渡す [[WordRanking, groups], ...]。その板が出ていなければ、もとの説明文のまま。
  def rankings_meta_description(boards)
    base = t("rankings.index.description")
    _ranking, groups = boards.find { |ranking, _groups| ranking.key == META_TOP_KEY }
    top = groups&.first
    return base if top.nil?

    t("rankings.index.meta_top", value: number_with_delimiter(top[:value])) + base
  end

  # 畳みきれなかった語(WordRanking::FOLD_LIMIT を超えたぶん)の続き。同じ並びの単語一覧のうち、
  # その組が始まるページへ渡す(下の順位の組は一覧の 2 ページ目以降から始まる)。1 ページ目は page を付けない。
  def rank_fold_rest_path(ranking, group)
    page = group[:offset] / WordsController::PER_PAGE + 1
    words_path(sort: ranking.key, page: (page if page > 1))
  end
end
