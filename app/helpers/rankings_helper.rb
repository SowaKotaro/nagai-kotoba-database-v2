module RankingsHelper
  # meta description の頭で名指しする順位表(このサイトの看板の数)。
  META_TOP_KEY = "length_desc".freeze
  # 名指しする語の長さの上限。説明文は約 120 字で切られるので(ApplicationHelper#page_description)、
  # これより長い語は名指しせず、もとの説明文だけにする(語の途中で切れた説明文にしない)。
  META_TOP_SURFACE_MAX_LENGTH = 60

  # /rankings の meta description。「読みが長い言葉」の 1 位(WordRanking#board が決めた組の代表)を頭に置く。
  # boards はコントローラが渡す [[WordRanking, groups], ...]。その板が出ていなければ、もとの説明文のまま。
  def rankings_meta_description(boards)
    base = t("rankings.index.description")
    _ranking, groups = boards.find { |ranking, _groups| ranking.key == META_TOP_KEY }
    top = groups&.first
    return base if top.nil? || top[:representative][:surface].length > META_TOP_SURFACE_MAX_LENGTH

    key = top[:count] > 1 ? "meta_top_tied" : "meta_top"
    t("rankings.index.#{key}", surface: top[:representative][:surface],
                               value: number_with_delimiter(top[:value]), count: number_with_delimiter(top[:count])) + base
  end

  # 畳みきれなかった語(WordRanking::FOLD_LIMIT を超えたぶん)の続き。同じ並びの単語一覧のうち、
  # その組が始まるページへ渡す(下の順位の組は一覧の 2 ページ目以降から始まる)。1 ページ目は page を付けない。
  def rank_fold_rest_path(ranking, group)
    page = group[:offset] / WordsController::PER_PAGE + 1
    words_path(sort: ranking.key, page: (page if page > 1))
  end
end
