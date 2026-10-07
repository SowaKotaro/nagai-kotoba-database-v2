# 新着単語の Atom フィード(Issue 28)。注釈された順に新しいものから。
atom_feed(language: "ja", root_url: SiteUrl.absolute("/"), url: SiteUrl.absolute("/words.atom")) do |feed|
  feed.title(t("words.feed.title"))
  feed.updated(@words.first&.annotated_at)

  @words.each do |word|
    feed.entry(word, url: SiteUrl.absolute(word_path(word)), updated: word.annotated_at) do |entry|
      entry.title(word.surface)
      entry.content(word_lead_sentence(word), type: "text")
    end
  end
end
