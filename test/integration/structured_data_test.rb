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
    get words_path
    crumb = find_type("BreadcrumbList")
    names = crumb["itemListElement"].map { |e| e["name"] }
    assert_includes names, I18n.t("layouts.breadcrumbs_home")
    assert_equal (1..crumb["itemListElement"].size).to_a,
                 crumb["itemListElement"].map { |e| e["position"] }
  end

  test "単語詳細に語義ごとの DefinedTerm と DefinedTermSet が出力される" do
    word = words(:abc_murder)
    get word_path(word)

    graph = json_ld_objects.find { |o| o["@graph"] }["@graph"]
    set = graph.find { |n| n["@type"] == "DefinedTermSet" }
    assert_equal "#{HOST}/#termset", set["@id"]

    term = graph.find { |n| n["@type"] == "DefinedTerm" }
    assert_equal word.surface, term["name"]
    assert_equal word_senses(:murder).reading, term["alternateName"]
    assert_equal "#{HOST}/#termset", term["inDefinedTermSet"]
    assert_includes term["description"], "日本語の長い言葉"
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
end
