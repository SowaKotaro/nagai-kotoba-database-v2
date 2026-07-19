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

  # 運営者(Organization)ノードの識別子。WebSite の publisher から参照する。
  def organization_id = absolute_site_url("/#organization")

  # 全ページ共通: サイト自身(WebSite)+運営者(Organization)+検索アクション。
  # 運営者情報は E-E-A-T(情報源の明示)のために出力し、連絡先は About と同じ公開メールを使う。
  def website_json_ld
    website = {
      "@type" => "WebSite",
      "name" => t("layouts.brand"),
      "url" => absolute_site_url("/"),
      "inLanguage" => "ja",
      "publisher" => { "@id" => organization_id },
      "potentialAction" => {
        "@type" => "SearchAction",
        "target" => {
          "@type" => "EntryPoint",
          "urlTemplate" => absolute_site_url("/words?q={search_term_string}")
        },
        "query-input" => "required name=search_term_string"
      }
    }
    organization = {
      "@type" => "Organization",
      "@id" => organization_id,
      "name" => t("layouts.brand"),
      "url" => absolute_site_url("/about"),
      "logo" => absolute_site_url("/icon.svg"),
      "email" => t("pages.about.contact_email")
    }
    json_ld_tag("@context" => "https://schema.org", "@graph" => [ website, organization ])
  end

  # About の FAQ(items = [{ question:, answer: }, ...])を FAQPage にする。
  # 文言は pages.about.faq_items(i18n)を画面表示と共用し、内容の食い違いを防ぐ。
  def faq_json_ld(items)
    json_ld_tag(
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" => items.map do |item|
        {
          "@type" => "Question",
          "name" => item[:question],
          "acceptedAnswer" => { "@type" => "Answer", "text" => item[:answer] }
        }
      end
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

  # 収録データのライセンス。DefinedTermSet(CreativeWork 派生)に付与する。
  # DefinedTerm(Intangible 派生)は license を持てないため Set 側に置く。
  CC_BY_URL = "https://creativecommons.org/licenses/by/4.0/deed.ja".freeze

  # 単語詳細: 語義ごとの DefinedTerm と、それらが属する DefinedTermSet。
  # 読み・文字数・韻・ジャンル等の属性を PropertyValue として添え、
  # 検索エンジンや LLM が本文を読まずに引用できる粒度まで構造化する(LLMO)。
  def word_json_ld(word)
    terms = word.word_senses.each.with_index(1).map do |sense, position|
      word_sense_term(word, sense, position)
    end

    graph = [
      { "@type" => "DefinedTermSet", "@id" => defined_term_set_id,
        "name" => t("layouts.brand"), "url" => absolute_site_url("/"),
        "inLanguage" => "ja", "license" => CC_BY_URL }
    ] + terms

    json_ld_tag("@context" => "https://schema.org", "@graph" => graph)
  end

  private

  # 語義1件を DefinedTerm ノードにする。@id の #sense-N は語義カードの番号(1始まり)に対応。
  def word_sense_term(word, sense, position)
    url = absolute_site_url(word_path(word))
    {
      "@type" => "DefinedTerm",
      "@id" => "#{url}#sense-#{position}",
      "name" => word.surface,
      "alternateName" => word_sense_alternate_names(sense),
      "description" => word_sense_lead_sentence(word, sense),
      "url" => url,
      "identifier" => word.id.to_s,
      "inLanguage" => "ja",
      "inDefinedTermSet" => { "@id" => defined_term_set_id },
      "additionalProperty" => word_sense_properties(sense)
    }
  end

  # 別名 = 読み + 別表記(表記・読み)。重複と空文字は除く。
  def word_sense_alternate_names(sense)
    names = [ sense.reading ] +
            sense.word_sense_variants.flat_map { |variant| [ variant.surface, variant.reading ] }
    names.compact_blank.uniq
  end

  # 語義の属性を PropertyValue の配列にする。未登録(nil・空)の属性は出力しない。
  # 名前は画面表示と同じ i18n を使い、HTML と構造化データの語彙を揃える。
  def word_sense_properties(sense)
    [
      [ WordSense.human_attribute_name(:reading), sense.reading ],
      [ t("words.show.reading_length"), sense.reading_length ],
      [ t("words.show.mora_count"), sense.mora_count ],
      [ WordSense.human_attribute_name(:rhythm_pattern), sense.rhythm_pattern ],
      [ t("words.show.vowel_pattern"), sense.vowel_pattern.presence ],
      [ WordSense.human_attribute_name(:genre), genre_path_name(sense.genre) ],
      [ WordSense.human_attribute_name(:part_of_speech), sense.part_of_speech&.name ],
      [ WordSense.human_attribute_name(:entity_type), sense.entity_type&.name ],
      [ t("words.show.origins"), sense.word_origins.map(&:name).join("、").presence ]
    ].filter_map do |name, value|
      { "@type" => "PropertyValue", "name" => name, "value" => value } if value
    end
  end

  # ジャンルを「大 › 中 › 小」のパス文字列にする(リード文と同じ区切り)。
  def genre_path_name(genre)
    genre&.self_and_ancestors&.map(&:name)&.join(t("words.lead.genre_separator"))
  end
end
