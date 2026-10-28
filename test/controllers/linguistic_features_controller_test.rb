require "test_helper"

# 言語学的特徴から探すページ(/linguistic_features)。件数の集計は PublishedSenseCountsTest、
# 定義(説明の最初の 1 文)の切り出しは LinguisticFeatureGlossaryTest で見る。
class LinguisticFeaturesControllerTest < ActionDispatch::IntegrationTest
  test "誰でも見られ(index 可)、公開語義のある特徴だけを用語解説の順に、定義と例と件数つきで絞り込みへリンクする" do
    # 公開語に付いていない特徴(未注釈の語にだけ付いた促音化)は出さない
    sokuon = LinguisticFeature.create!(name: "促音化")
    WordSenseFeature.create!(word_sense: word_senses(:pending), linguistic_feature: sokuon,
                             target: "憂鬱", target_reading: "ゆううつ", target_start: 6)

    get linguistic_features_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("linguistic_features.index.title")
    assert_select "meta[name=robots]", count: 0

    # 並びは用語解説の順(連濁 → 重箱読み)。ABC殺人事件(murder)に付いた 2 つだけで、どちらも 1 語義
    items = css_select(".feature-hub__item")
    assert_equal [ "連濁", "重箱読み" ], items.map { |item| item.at_css(".feature-hub__name").text }
    assert_select "a.feature-hub__name[href=?]", words_path(linguistic_feature_id: linguistic_features(:rendaku).id)
    assert_select ".feature-hub__count", text: I18n.t("linguistic_features.index.count", count: 1), count: 2
    assert_select "a.feature-hub__name[href=?]", words_path(linguistic_feature_id: sokuon.id), count: 0

    # 説明は定義の 1 文だけ、例は頭から EXAMPLE_LIMIT 件
    rendaku = LinguisticFeatureGlossary.find("連濁")
    assert_equal rendaku.definition, items.first.at_css(".feature-hub__description").text
    examples = rendaku.examples.first(LinguisticFeaturesController::EXAMPLE_LIMIT)
                      .join(I18n.t("shared.feature_glossary.examples_separator"))
    assert_equal I18n.t("linguistic_features.index.examples", examples: examples), items.first.at_css(".feature-hub__examples").text.strip
  end
end
