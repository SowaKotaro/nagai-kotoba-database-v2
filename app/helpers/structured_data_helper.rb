# schema.org の構造化データ(JSON-LD)を出力する(Issue 16)。
# リッチリザルトや AI 検索がページ構造を誤りなく解釈・引用できるようにする。
module StructuredDataHelper
  # サイト全体の用語集(DefinedTermSet)の識別子。各 DefinedTerm から参照する。
  def defined_term_set_id = absolute_site_url("/#termset")

  # <script type="application/ld+json"> を安全に出力する。
  # </script> 等の混入を防ぐため JSON 内の < > & をエスケープする。
  def json_ld_tag(data)
    content_tag :script, json_escape(data.to_json).html_safe, type: "application/ld+json"
  end

  # 全ページ共通: サイト自身と検索アクション(サイトリンク検索ボックス候補)。
  def website_json_ld
    json_ld_tag(
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => t("layouts.brand"),
      "url" => absolute_site_url("/"),
      "inLanguage" => "ja",
      "potentialAction" => {
        "@type" => "SearchAction",
        "target" => {
          "@type" => "EntryPoint",
          "urlTemplate" => absolute_site_url("/words?q={search_term_string}")
        },
        "query-input" => "required name=search_term_string"
      }
    )
  end

  # パンくず(items = [[ラベル, パス(現在地は nil)], ...])を BreadcrumbList にする。
  def breadcrumb_json_ld(items)
    elements = items.each_with_index.map do |(label, path), index|
      {
        "@type" => "ListItem",
        "position" => index + 1,
        "name" => label,
        "item" => absolute_site_url(path || request.path)
      }
    end
    json_ld_tag(
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => elements
    )
  end

  # 単語詳細: 語義ごとの DefinedTerm と、それらが属する DefinedTermSet。
  def word_json_ld(word)
    terms = word.word_senses.map do |sense|
      {
        "@type" => "DefinedTerm",
        "name" => word.surface,
        "alternateName" => sense.reading,
        "description" => word_sense_lead_sentence(word, sense),
        "inDefinedTermSet" => defined_term_set_id
      }
    end

    graph = [
      { "@type" => "DefinedTermSet", "@id" => defined_term_set_id,
        "name" => t("layouts.brand"), "url" => absolute_site_url("/") }
    ] + terms

    json_ld_tag("@context" => "https://schema.org", "@graph" => graph)
  end
end
