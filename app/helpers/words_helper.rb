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
end
