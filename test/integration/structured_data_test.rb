require "test_helper"

# 構造化データ(JSON-LD / Issue 16)の結合テスト。
class StructuredDataTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "全ページに WebSite + SearchAction が出力される" do
    get root_path
    site = find_type("WebSite")
    assert_equal I18n.t("layouts.brand"), site["name"]
    assert_equal "#{HOST}/", site["url"]
    action = site["potentialAction"]
    assert_equal "SearchAction", action["@type"]
    assert_equal "#{HOST}/words?q={search_term_string}", action["target"]["urlTemplate"]
  end

  test "パンくずのあるページに BreadcrumbList が出力される" do
    # パンくずを描画する主要な公開ページを一巡する(単語詳細は下の DefinedTerm テストで別途確認)
    [ words_path, genres_path, browse_path, about_path ].each do |path|
      get path
      crumb = find_type("BreadcrumbList")
      assert crumb, "#{path} に BreadcrumbList がない"
      names = crumb["itemListElement"].map { |e| e["name"] }
      assert_includes names, I18n.t("layouts.breadcrumbs_home")
      assert_equal (1..crumb["itemListElement"].size).to_a,
                   crumb["itemListElement"].map { |e| e["position"] }
    end
  end

  test "単語詳細に語義ごとの DefinedTerm と DefinedTermSet が出力される" do
    word = words(:abc_murder)
    get word_path(word)

    graph = json_ld_objects.find { |o| o["@graph"] }["@graph"]
    set = graph.find { |n| n["@type"] == "DefinedTermSet" }
    assert_equal "#{HOST}/#termset", set["@id"]
    assert_equal StructuredDataHelper::CC_BY_URL, set["license"]
    assert_equal "ja", set["inLanguage"]

    term = graph.find { |n| n["@type"] == "DefinedTerm" }
    assert_equal word.surface, term["name"]
    assert_equal [ word_senses(:murder).reading ], term["alternateName"]
    assert_equal({ "@id" => "#{HOST}/#termset" }, term["inDefinedTermSet"])
    assert_equal "#{HOST}/words/#{word.id}#sense-1", term["@id"]
    assert_equal "#{HOST}/words/#{word.id}", term["url"]
    assert_equal word.id.to_s, term["identifier"]
    assert_includes term["description"], "日本語の長い言葉"
  end

  test "DefinedTerm の additionalProperty に語義の属性が出力される" do
    get word_path(words(:abc_murder))
    properties = defined_term_properties

    assert_equal "さつじんじけん", properties[WordSense.human_attribute_name(:reading)]
    assert_equal 7, properties[I18n.t("words.show.reading_length")]
    assert_equal 7, properties[I18n.t("words.show.mora_count")]
    assert_equal "satsujinjiken", properties[WordSense.human_attribute_name(:rhythm_pattern)]
    assert_equal "auiie", properties[I18n.t("words.show.vowel_pattern")]
    assert_equal "文学 › 日本文学 › 小説", properties[WordSense.human_attribute_name(:genre)]
    assert_equal "名詞", properties[WordSense.human_attribute_name(:part_of_speech)]
    assert_equal "書籍名", properties[WordSense.human_attribute_name(:entity_type)]
    assert_equal "漢語", properties[I18n.t("words.show.origins")]
  end

  test "未登録の属性は additionalProperty に出力されず別表記は alternateName に入る" do
    get word_path(words(:curry)) # ジャンル・エンティティ未登録、別表記あり
    properties = defined_term_properties

    assert_nil properties[WordSense.human_attribute_name(:genre)]
    assert_nil properties[WordSense.human_attribute_name(:entity_type)]

    term = flat_map_graph.find { |n| n["@type"] == "DefinedTerm" }
    assert_includes term["alternateName"], word_sense_variants(:curry_variant).surface
  end

  test "JSON-LD は妥当な JSON として解析できる(エスケープ健全性)" do
    get word_path(words(:abc_murder))
    assert_operator json_ld_objects.size, :>=, 3 # WebSite / BreadcrumbList / DefinedTerm graph
  end

  private

  def json_ld_objects
    Nokogiri::HTML(response.body)
      .css("script[type='application/ld+json']")
      .map { |node| JSON.parse(node.text) }
  end

  def find_type(type)
    json_ld_objects.find { |o| o["@type"] == type } || flat_map_graph.find { |o| o["@type"] == type }
  end

  def flat_map_graph
    json_ld_objects.flat_map { |o| o["@graph"] || o }
  end

  # 最初の DefinedTerm の additionalProperty を { name => value } に変換する。
  def defined_term_properties
    term = flat_map_graph.find { |n| n["@type"] == "DefinedTerm" }
    term["additionalProperty"].to_h { |p| [ p["name"], p["value"] ] }
  end
end
