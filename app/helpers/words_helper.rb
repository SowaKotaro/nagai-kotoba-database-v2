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

  # 単語詳細の自己完結リード文(定義文)を決定的に組み立てる(Issue 18)。
  # 読み・文字数・モーラ・ジャンルという構造データを散文に起こし、
  # meta description(Issue 14)や JSON-LD の description(Issue 16)にも流用する。
  # 語義が1つならその語義の定義文をそのまま使う。複数(同音異義語)なら、共通の見出し文に
  # 語義数と各語義の意味を①②…で並べる(ジャンルは下の語義カードにあるので省く)。
  # 語義が無ければ空文字を返す。
  def word_lead_sentence(word)
    senses = word.word_senses.sort_by(&:id)
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
      path = sense.genre.self_and_ancestors.map(&:name).join(t("words.lead.genre_separator"))
      sentence += t("words.lead.genre", path: path)
    end

    sentence += t("words.lead.meaning", meaning: sense.meaning.strip) if sense.meaning.present?

    sentence
  end

  # 単一ファセット(Issue 17)の一覧に付ける動的見出し(title/h1 兼用)。
  # インデックス対象の単一ファセットでなければ nil を返す(=素の「単語一覧」を使う)。
  FACET_MASTERS = {
    genre_id: Genre, part_of_speech_id: PartOfSpeech,
    entity_type_id: EntityType, word_origin_id: WordOrigin,
    linguistic_feature_id: LinguisticFeature
  }.freeze

  # マスタを持たず、値(かな1文字)をそのまま見出しに使うファセット。
  CHAR_FACET_KEYS = %i[first_char last_char].freeze

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

  # キーワード検索の結果行で「別表記だけが一致した」ことを示すための、一致した別表記(Issue 72)。
  # 表層形・読みが直接一致している語は、なぜ出たのかが自明なので空を返す(注記を出さない)。
  # 突き合わせは MySQL の照合順序(utf8mb4_0900_as_ci)に寄せて、ひらがな⇔カタカナと
  # 大文字小文字だけを畳む(清濁は畳まない)。畳み方が DB と完全一致しない場合でも、
  # 注記が出ないだけで検索結果自体は変わらない。
  def matched_variants(word, query)
    needle = fold_for_keyword_match(query)
    return [] if needle.blank?
    return [] if fold_for_keyword_match(word.surface).include?(needle)
    return [] if word.word_senses.any? { |sense| fold_for_keyword_match(sense.reading).include?(needle) }

    word.word_senses.flat_map(&:word_sense_variants).select do |variant|
      fold_for_keyword_match(variant.surface).include?(needle) ||
        fold_for_keyword_match(variant.reading).include?(needle)
    end.uniq(&:surface)
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
  def canonical_index_path(search, page)
    facet = search.indexable_facet
    params =
      if facet
        { facet.first => facet.last } # 単一ファセットは実際のリンクと同じスカラ形
      elsif search.conditions?
        search.to_query_params.sort.to_h # 複数条件はキー順に整列した自身
      else
        {}
      end
    params[:page] = page if page > 1
    words_path(params)
  end

  # 文字の軸(先頭文字・末尾文字)で複数の文字を渡しうるリンクのパス。
  # 1文字だけのときは配列形(`first_char[]=ア`)ではなくスカラ形(`first_char=ア`)にする。
  # 配列形は canonical(スカラ形)と URL が食い違い、Search Console に
  # 「代替ページ(適切な canonical タグあり)」として無駄に積み上がるため。
  def char_facet_words_path(**chars)
    words_path(chars.transform_values { |value| Array(value).size == 1 ? Array(value).first : value })
  end

  private

  # キーワード突き合わせ用の畳み込み。ひらがな→カタカナ(同じ並びの2つの範囲)と、
  # 欧字の大文字小文字だけを吸収する。
  HIRAGANA_RANGE = "ぁ-ゖ".freeze
  KATAKANA_RANGE = "ァ-ヶ".freeze
  private_constant :HIRAGANA_RANGE, :KATAKANA_RANGE

  def fold_for_keyword_match(text)
    text.to_s.strip.tr(HIRAGANA_RANGE, KATAKANA_RANGE).downcase
  end

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
