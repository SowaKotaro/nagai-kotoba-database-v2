xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
  # インデックスを許可している単一条件の一覧。URL は canonical と同じ形(WordsHelper#canonical_index_path)にする。
  # lastmod は付けない(面の更新日時を正確に出せない)。
  @facets.each do |facet|
    xml.url do
      xml.loc SiteUrl.absolute(words_path(facet.key => facet.value))
    end
  end
end
