xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
  # 静的ページ(トップ・単語一覧・ジャンル・About)。lastmod は付けない。
  [ "/", words_path, genres_path, about_path ].each do |path|
    xml.url do
      xml.loc "#{@host}#{path}"
    end
  end

  # 公開(注釈済み)の全単語詳細。lastmod は更新日時。
  @words.find_each do |word|
    xml.url do
      xml.loc "#{@host}#{word_path(word)}"
      xml.lastmod word.updated_at.iso8601
    end
  end
end
