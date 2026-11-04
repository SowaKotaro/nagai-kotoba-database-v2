module HomeHelper
  # ホームの検索バーの下に並べる探し方の入口(docs/design.md §5.2)。SANKOU! のトップと同じく、選択肢を持つものは
  # 押すとその場で選択肢が開くボタン(∨)にし、そのほかはそのページへ進むボタン(→)にする。
  # 並びは、開くボタン(SearchWayMenus::KEYS の順)→ 索引 → ランダム → 詳細検索。
  # 探すページを持つ探し方は、ヘッダーの「検索」メニュー(ApplicationHelper#search_ways)と同じ語と行き先を使い、
  # 開いたパネルの末尾にそのページ(全部を並べたもの)へのリンクを添える。
  def home_search_ways
    @home_search_ways ||= begin
      pages = search_ways.index_by { |way| way[:key] }
      menus = SearchWayMenus.all.filter_map do |key, options|
        next if options.empty?

        page = pages[key]
        { key:, label: page ? page[:label] : t("home.index.ways.#{key}"),
          options: options.map { |option| [ search_way_option_label(option.name), words_path(option.params) ] },
          more: page && [ t("home.index.ways.more", name: page[:label]), page[:path] ] }
      end
      menus + [
        pages[:browse],
        # 押すたびに行き先が変わるので、検索エンジンには辿らせない(フッター・単語詳細の同じリンクと同じ)
        { key: :random, label: t("home.index.ways.random"), path: random_words_path, rel: "nofollow" },
        pages[:advanced_search]
      ]
    end
  end

  # 探し方の入口を描いた結果(フラグメントキャッシュ)の鍵。選択肢(SearchWayMenus.all。1 時間キャッシュ)が変わったときだけ描き直す。
  # 選択肢は 90 ほどのリンクになり、毎リクエスト組んで描くとそれだけでホームの描画が数 ms 延びる
  def home_search_ways_cache_key
    [ :home_search_ways, ActiveSupport::Digest.hexdigest(SearchWayMenus.all.to_s) ]
  end

  # 選択肢の語。読みの長さだけは区切り(SearchWayMenus::READING_LENGTH_BANDS)から組む
  def search_way_option_label(name)
    return name unless name.is_a?(Range)
    return t("home.index.ways.length.at_least", min: name.begin) if name.end.nil?

    t("home.index.ways.length.exact", count: name.begin)
  end

  # ランキングの下の「数字で見る長い言葉」に出す数(統計ページの数字の壁の行のキー)と、押したときに送る統計ページの章(id は stats/index)。
  # 平均・割合・上限まで埋まっていく数(頭文字の種類・使用ジャンルなど)は出さず、天井無しに増えていく数だけを選ぶ
  # (2026-11-03 オーナー指示。docs/design.md §5.2)
  HOME_STATS_FIGURES = {
    words: "timeline", senses: "number-wall", variants: "number-wall", homophones: "number-wall",
    total_reading_chars: "number-wall", days_open: "timeline"
  }.freeze

  # 語・値・単位は、統計ページの数字の壁の同じ行(StatsHelper#stats_number_wall)をそのまま出す
  def home_stats_figures(wall)
    rows = stats_number_wall(wall).flat_map { |group| group[:rows] }.index_by { |row| row[:key] }
    HOME_STATS_FIGURES.map { |key, anchor| rows.fetch(key).merge(path: stats_path(anchor:)) }
  end
end
