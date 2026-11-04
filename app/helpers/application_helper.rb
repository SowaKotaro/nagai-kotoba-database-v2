module ApplicationHelper
  # <title> と og:title に使う共通のページタイトル。
  # ページ側が content_for(:title) を設定していればブランド名と連結する。
  def page_title
    content_for?(:title) ? "#{content_for(:title)} | #{t('layouts.brand')}" : t("layouts.brand")
  end

  # meta description / og:description。ページ側の content_for(:description) を優先し、
  # 無ければサイト既定の説明(文節の配列。つないで使う)にフォールバックする。検索スニペット向けに1行・約120字に整える。
  def page_description
    raw = content_for?(:description) ? content_for(:description) : t("home.index.description").join
    raw.to_s.squish.truncate(120)
  end

  # canonical と og:url。既定は本番ホスト + 現在のパス(クエリは含めない)。
  # ファセット等でパスを差し替えたいページは canonical_path(...) で設定する(Issue 17)。
  def canonical_url
    SiteUrl.absolute(@canonical_path.presence || request.path)
  end

  # canonical のパスをページ側から指定する。
  # ここだけ content_for を使わないのは二重エスケープを避けるため。content_for は値を
  # HTML エスケープして貯めるので、クエリの & が &amp; になり、レイアウトの <%= %> で
  # もう一度エスケープされて ?a=1&amp;amp;b=2 になる。ブラウザ/クローラから見ると
  # 「amp;b」という実在しないパラメータ名の URL が canonical に出てしまう。
  def canonical_path(path)
    @canonical_path = path
  end

  # 文ごとの文節の配列(ja.yml)を、文ごとに行を分け、文の中は文節の切れ目でだけ折れる形に組む(.phrase-sentence と対)。
  # 語の途中(「見つかりませんで／した」)や語尾だけ(「…全順位を／辿れます。」)の折れを防ぐ。
  # 文節の末尾の空白(「棒 → 」)は塊の外に出す。塊の中に置くと行末の空白として消え、次の文節と詰まって見える
  def phrased_sentences(sentences)
    safe_join(sentences.map do |phrases|
      tag.span(safe_join(phrases.map { |phrase| phrase_with_trailing_space(phrase) }, tag.wbr), class: "phrase-sentence")
    end)
  end

  # 用語解説の例(「硫黄 + 島 → いおうじま（シマ → ジマ）」)を 1 つずつ塊にして区切りでつなぐ(.phrase と対)。
  # 例の途中(「（ソラ／→ ゾラ）」)では折らず、区切りの後ろで折る。label(「例: 」)は最初の例の塊に含め、ラベルだけが行に残らないようにする。
  # 区切りは丸ごと前の例の塊に含め、折らない片(.phrase-mark)にする。塊の外に出すと、「／」だけの行や、
  # 塊が幅いっぱいに折れたときに区切りの全角空白だけの行と、全角空白で始まる行ができた。
  # 1 つの例で幅に収まらないときは、例の中の切れ目(example_parts)で折る
  def feature_examples(examples, label: nil)
    separator = t("shared.feature_glossary.examples_separator")
    safe_join(examples.each_with_index.map do |example, index|
      *heads, tail = example_parts("#{label if index.zero?}#{example}")
      parts = heads.map { |part| phrase_with_trailing_space(part) }
      parts << tag.span(safe_join([ tail, (tag.span(separator, class: "phrase-mark") unless index == examples.size - 1) ]), class: "phrase")
      tag.span(safe_join(parts, tag.wbr), class: "phrase")
    end, tag.wbr)
  end

  # 名前(ジャンルの分類名・絞り込みの条件の値・区画の見出し)を、「・」の後ろ・「（」の前・空白でだけ折れる形にする(.phrase と対)。
  # 語の途中(「スポー／ツ」「部分一／致」)や最後の 1 字(「出版／物」)では折らない。切れ目ごとに塊にするのは、
  # keep-all では WebKit が「（」の後ろで折ったため。1 つの塊で幅に収まらないときだけ、塊の中で折れる
  def phrased_name(text)
    safe_join(text.to_s.split(/(?<=[・ ])|(?=（)/).map { |part| phrase_with_trailing_space(part) }, tag.wbr)
  end

  # og:image の絶対URL。ページ側の content_for(:og_image) を優先し、無ければ既定カード。
  def page_og_image
    path = content_for?(:og_image) ? content_for(:og_image).to_s : SiteUrl::DEFAULT_OG_IMAGE_PATH
    SiteUrl.absolute(path)
  end

  # og:image:alt。画像を差し替えたページ(単語の共有カード)は content_for(:og_image_alt) でその画像の説明を置く。
  def page_og_image_alt
    content_for?(:og_image_alt) ? content_for(:og_image_alt) : t("layouts.og_image_alt")
  end

  # og:type。単語詳細などは content_for(:og_type) で "article" を指定できる。
  def page_og_type
    content_for?(:og_type) ? content_for(:og_type).to_s : "website"
  end

  # meta robots の値(Issue 43)。インデックス解禁前(INDEXING_ENABLED 未設定)は
  # ページ個別の指定より優先して全ページ noindex にする。解禁後はページ個別の
  # content_for(:robots)(ファセット・/search 等。Issue 17)に従う。
  def page_robots
    Rails.application.config.x.indexing_enabled ? content_for(:robots) : "noindex"
  end

  # 探し方の入口(詳細検索から切り出した探し方のページと、詳細検索)。ヘッダーの「検索」メニューが並べ、
  # ホームの検索バーの下のボタン(HomeHelper#home_search_ways)も、この語と行き先を使う(画面ごとに同じ探し方の名前が食い違わないように)。
  # 並びは、何についての言葉か(ジャンル → 何の名前か → 言葉のしくみ)→ 読みの形 → 全条件。
  # key は、ホームで選択肢が開くボタン(SearchWayMenus::KEYS)と突き合わせる名前。
  # icon はヘッダーのメニューだけが使う(単語詳細の関連データ・詳細検索の区画と同じ印)。
  def search_ways
    [
      { key: :genre, label: t("layouts.nav.genres"), path: genres_path, icon: "tag" },
      { key: :entity_type, label: t("layouts.nav.entity_types"), path: entity_types_path, icon: "cube" },
      { key: :linguistic_feature, label: t("layouts.nav.linguistic_features"), path: linguistic_features_path, icon: "pen_nib" },
      { key: :browse, label: t("layouts.nav.browse"), path: browse_path, icon: "grid_nine" },
      { key: :advanced_search, label: t("layouts.nav.advanced_search"), path: search_path, icon: "funnel" }
    ]
  end

  # 収録リクエスト(Issue 75)を受け付けているか。荒らされたときは環境変数 REQUESTS_ENABLED で
  # 止められるようにしてあり、停止中は公開側の導線そのものを出さない。
  def requests_open?
    Rails.application.config.x.requests_enabled
  end

  # GA4 の測定ID(G-XXXXXXX)。本番の環境変数から読む。未設定なら計測タグを出さない(Issue 19)。
  def ga_measurement_id
    ENV["GA4_MEASUREMENT_ID"].presence
  end

  def analytics_enabled?
    ga_measurement_id.present?
  end

  # 各サーチコンソールの所有権確認メタ(DNS 確認が使えない場合の代替。任意)。
  # 値はいずれも環境変数から。未設定ならタグを出さない。
  def google_site_verification = ENV["GOOGLE_SITE_VERIFICATION"].presence
  def bing_site_verification = ENV["BING_SITE_VERIFICATION"].presence

  private

  def phrase_with_trailing_space(phrase)
    text = phrase.rstrip
    safe_join([ tag.span(text, class: "phrase"), phrase.delete_prefix(text) ])
  end

  # 例を、演算子の後ろ(「硫黄 + 」「島 → 」)・「・」の後ろ・全角の括弧書きの前で切る。括弧書きの中は句読点の後ろでだけ切り、
  # 空白では割らない(320px 幅で「（シマ →／ジマ）」と割れた)。読みを添える半角の括弧(「菅(すが)」)では切らない
  def example_parts(example)
    example.split(/(（[^）]*）)/).reject(&:empty?).flat_map do |segment|
      segment.split(segment.start_with?("（") ? /(?<=[、。])/ : /(?<=[+→] |・)/)
    end
  end
end
