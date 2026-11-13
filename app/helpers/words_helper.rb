module WordsHelper
  # 見出し語を Web(アプリ外)で検索するための外部リンク先。
  WEB_SEARCH_BASE_URL = "https://www.google.com/search".freeze

  def web_search_url(query)
    "#{WEB_SEARCH_BASE_URL}?#{{ q: query }.to_query}"
  end

  # X 共有の本文。X の投稿は 280 単位が上限で、全角(CJK)は 1 文字 = 2 単位、
  # URL は実際の長さに関わらず 23 単位(t.co 短縮)を消費する。本文と URL の区切り
  # 1 単位も引くと本文に使えるのは 256 単位 = 全角 128 文字。余裕を見て 125 文字で丸める。
  X_SHARE_TEXT_LIMIT = 125

  def x_share_text(word, lead)
    (lead.presence || word.surface).squish.truncate(X_SHARE_TEXT_LIMIT, omission: "…")
  end

  # 単語ごとの共有カード(og:image)。焼ける環境の、読みのある語だけ(それ以外は nil で既定のカードのまま)。
  def word_share_card(word)
    card = WordShareCard.new(word)
    card if card.renderable?
  end

  # 一覧の並び順セレクタの選択肢(WordSort::SELECTABLE_KEYS の順)。シャッフルは並び順ではないので選択肢に入れないが、
  # シャッフル中だけは選べない「シャッフル中」を先頭に出して選択済みにする。出さないと先頭の既定の並びが選ばれて見え、
  # それを選び直しても change が起きないので、既定の並びへ戻れない
  def sort_select_options(sort)
    options = WordSort::SELECTABLE_KEYS.map { |key| [ t("words.index.sort.options.#{key}"), key ] }
    return options_for_select(options, sort.key) unless sort.shuffle?

    options_for_select([ [ t("words.index.sort.shuffling"), WordSort::SHUFFLE_KEY ], *options ],
                       selected: WordSort::SHUFFLE_KEY, disabled: WordSort::SHUFFLE_KEY)
  end

  # 単語詳細の自己完結リード文(定義文)を決定的に組み立てる(Issue 18)。
  # 読み・文字数・モーラ・ジャンルという構造データを散文に起こし、
  # meta description(Issue 14)や JSON-LD の description(Issue 16)にも流用する。
  # 語義が1つならその語義の定義文をそのまま使う。複数(同音異義語)なら、共通の見出し文に
  # 語義数と各語義の意味を①②…で並べる(ジャンルは下の語義カードにあるので省く)。
  # 語義が無ければ空文字を返す。
  def word_lead_sentence(word)
    senses = word.ordered_senses
    return "" if senses.empty?
    return word_sense_lead_sentence(word, senses.first) if senses.one?

    word_headline_sentence(word, senses) +
      t("words.lead.sense_count", count: senses.size) +
      numbered_sense_meanings(senses)
  end

  # 語義単位の定義文。JSON-LD(Issue 16)の語義ごとの description にも使う。
  def word_sense_lead_sentence(word, sense)
    sentence = t("words.lead.base",
                 surface: word.surface,
                 reading: sense.reading,
                 metrics: sense_metrics(sense))

    if sense.genre
      path = sense.genre.path_text
      sentence += t("words.lead.genre", path: path)
    end

    sentence += t("words.lead.meaning", meaning: sense.meaning.strip) if sense.meaning.present?

    sentence
  end

  # 単一ファセット(Issue 17)の一覧に付ける動的見出し(title/h1 兼用)。
  # インデックス対象の単一ファセットでなければ nil を返す(=素の「単語一覧」を使う)。
  # マスタを引いて名前を見出しにする軸。実在しない id の検出と同じ対応表を使う
  # (片方だけ軸が増えると、見出しの出ない面や 404 にならない面が生まれるため)。
  FACET_MASTERS = WordSenseSearch::MASTER_FACETS

  # マスタを持たず、値(かな1文字)をそのまま見出しに使うファセット。
  CHAR_FACET_KEYS = IndexableFacets::KANA_FACET_KEYS

  # マスタを持たず、値(数値)をそのまま見出しに使うファセット。
  NUMERIC_FACET_KEYS = %i[reading_length mora_count].freeze

  def facet_heading(search)
    facet = search.indexable_facet
    return nil unless facet

    key, value = facet
    # 文字の軸(先頭文字・末尾文字)はマスタを引かず、文字そのものを見出しに使う。
    if CHAR_FACET_KEYS.include?(key)
      t("words.index.facet_heading.#{key}", char: value)
    # 数の軸(読みの文字数・モーラ数)も同じくマスタを引かない。
    elsif NUMERIC_FACET_KEYS.include?(key)
      t("words.index.facet_heading.#{key}", count: value.to_i)
    else
      name = FACET_MASTERS[key].where(id: value).pick(:name)
      name && t("words.index.facet_heading.default", name: name)
    end
  end

  # ファセット面の meta description に並べる例語の数と、例語ぜんぶ(かぎ括弧つき)の長さの上限。
  # 説明文は ApplicationHelper#page_description が約 120 字で切るので、見出しと件数を足しても収まる長さに抑える。
  FACET_EXAMPLE_LIMIT = 3
  FACET_EXAMPLES_MAX_LENGTH = 60

  # ファセット面の meta description。面ごとの件数と、このページの先頭の語を例に入れる(追加のクエリは引かない)。
  # 長い語は 1 語で数十字あるので、上限に収まるところまでを並べ、1 語も収まらなければ件数だけの文にする。
  def facet_meta_description(heading, total_count, words)
    examples = []
    words.first(FACET_EXAMPLE_LIMIT).each do |word|
      example = t("words.index.facet_meta_description.example", surface: word.surface)
      break if (examples.sum(&:length) + example.length) > FACET_EXAMPLES_MAX_LENGTH

      examples << example
    end
    key = examples.any? ? "with_examples" : "without_examples"
    t("words.index.facet_meta_description.#{key}",
      label: heading, count: number_with_delimiter(total_count), examples: examples.join)
  end

  # text のうち spans(SearchHighlight が求めた、検索条件に当たった箇所)を <mark> で囲む。無ければ text のまま。
  # 2 つ以上の条件が重なって当たった箇所(deep)は、濃く囲む印のクラスを足す。
  def search_highlighted(text, spans)
    return text if spans.blank?

    cursor = 0
    pieces = spans.flat_map do |span|
      before = text[cursor...span.range.begin]
      cursor = span.range.end
      [ before, tag.mark(text[span.range], class: [ "search-hit", ("search-hit--deep" if span.deep) ]) ]
    end
    safe_join(pieces << text[cursor..])
  end

  # 「シャッフルする」ボタンの遷移先。現在の絞り込みは保ったまま、シャッフルの一覧へ渡す。
  # シードは URL に載せない(サーバ側でリクエストごとに振る。WordSort)。href にシードを
  # 載せると描画のたびに未知の URL が生まれ、クローラの無限ループになるため。
  # これで絞り込み1つにつきシャッフルの URL はちょうど1本に収まる。
  def shuffle_words_path
    words_path(request.query_parameters.except("page", "sort", "seed")
                      .merge(sort: WordSort::SHUFFLE_KEY))
  end

  # canonical に使う正規化済みのパス(Issue 17)。
  # 単一ファセットは実際のリンクと同じスカラ形、それ以外は条件をキー順に整列した自身。
  #
  # 並び順(sort)も canonical に含める。既定以外の並びは「同じ集合の順列違い」なので
  # noindex になるが、noindex のページが**他の URL** を canonical に指すと、その指し先へ
  # noindex が伝播しうる(Google の公式ガイダンス)。含めないと /words?sort=… が揃って
  # /words を正規版に指名してしまい、サイトのハブごと巻き添えになる。自身を指させて断つ。
  # シャッフルの seed は URL に載せない値なので、canonical も seed 抜きの1本に寄せる
  # (指し先も noindex なので伝播しても害が無く、既知の seed 付き URL を1本に集約できる)。
  def canonical_index_path(search, page, sort = nil)
    facet = search.indexable_facet
    query =
      if facet
        { facet.first => facet.last } # 単一ファセットは実際のリンクと同じスカラ形
      elsif search.conditions?
        search.to_query_params.sort.to_h # 複数条件はキー順に整列した自身
      else
        {}
      end
    query[:sort] = sort.key if sort && !sort.default?
    query[:page] = page if page > 1
    words_path(query)
  end

  # 文字の軸(先頭文字・末尾文字)で複数の文字を渡しうるリンクのパス。
  # 1文字だけのときは配列形(`first_char[]=ア`)ではなくスカラ形(`first_char=ア`)にする。
  # 配列形は canonical(スカラ形)と URL が食い違い、Search Console に
  # 「代替ページ(適切な canonical タグあり)」として無駄に積み上がるため。
  def char_facet_words_path(**chars)
    words_path(chars.transform_values { |value| Array(value).size == 1 ? Array(value).first : value })
  end

  private

  # 読みの文字数・モーラ数。モーラ数は未算出のことがある。
  def sense_metrics(sense)
    metrics = [ t("words.show.chars", count: sense.reading_length) ]
    metrics << t("words.show.mora", count: sense.mora_count) if sense.mora_count
    metrics.join(t("words.lead.metrics_separator"))
  end

  # 複数語義に共通の見出し文。語義ごとに読みが違う場合は字数・モーラが定まらないため、
  # それらは添えずに読みだけを並べる。
  def word_headline_sentence(word, senses)
    readings = senses.map(&:reading).uniq
    if readings.one?
      t("words.lead.base", surface: word.surface, reading: readings.first,
                           metrics: sense_metrics(senses.first))
    else
      t("words.lead.base_multi_reading", surface: word.surface,
                                         readings: readings.map { |reading| t("words.lead.reading", reading:) }.join)
    end
  end

  # ①②… を振った意味の列挙。番号は語義カード(語義 01/02…)と同じ並び順に対応する。
  # 意味が未登録の語義は文にできないので飛ばす(番号は詰めない)。
  def numbered_sense_meanings(senses)
    senses.each_with_index.filter_map do |sense, index|
      next if sense.meaning.blank?

      t("words.lead.sense_meaning", number: circled_number(index + 1),
                                    meaning: ensure_sentence_end(sense.meaning.strip))
    end.join
  end

  CIRCLED_NUMBERS = ("①".."⑳").to_a.freeze

  def circled_number(number) = CIRCLED_NUMBERS[number - 1] || "(#{number})"

  # 意味は句点で終わるとは限らない。並べたときに次の語義と地続きにならないよう補う。
  SENTENCE_ENDINGS = /[。．.！？!?]\z/
  private_constant :SENTENCE_ENDINGS

  def ensure_sentence_end(text) = text.match?(SENTENCE_ENDINGS) ? text : "#{text}。"
end
