module WordsHelper
  # 単語詳細の自己完結リード文(定義文)を決定的に組み立てる(Issue 18)。
  # 読み・文字数・モーラ・ジャンルという構造データを散文に起こし、
  # meta description(Issue 14)や JSON-LD の description(Issue 16)にも流用する。
  # 代表として先頭(最小 id)の語義を用いる。語義が無ければ空文字を返す。
  def word_lead_sentence(word)
    sense = word.word_senses.min_by(&:id)
    return "" if sense.nil?

    metrics = [ t("words.show.chars", count: sense.reading_length) ]
    metrics << t("words.show.mora", count: sense.mora_count) if sense.mora_count

    sentence = t("words.lead.base",
                 surface: word.surface,
                 reading: sense.reading,
                 metrics: metrics.join(t("words.lead.metrics_separator")))

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
    entity_type_id: EntityType, word_origin_id: WordOrigin
  }.freeze

  def facet_heading(search)
    facet = search.indexable_facet
    return nil unless facet

    key, value = facet
    if key == :first_char
      t("words.index.facet_heading.first_char", char: value)
    else
      name = FACET_MASTERS[key].where(id: value).pick(:name)
      name && t("words.index.facet_heading.default", name: name)
    end
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
end
