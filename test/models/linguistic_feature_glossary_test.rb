require "test_helper"

# 言語学的特徴の用語解説(Issue 39)。config/linguistic_features_glossary.yml が単一ソース。
class LinguisticFeatureGlossaryTest < ActiveSupport::TestCase
  test "seed のマスタ名と1対1で、全項目に説明と3〜5件の具体例があり、名前で引ける" do
    assert_equal SeedCatalog::LINGUISTIC_FEATURES.sort, LinguisticFeatureGlossary.all.map(&:name).sort

    # 全項目に説明と3〜5件の具体例がある
    LinguisticFeatureGlossary.all.each do |entry|
      assert entry.description.present?, "#{entry.name} の説明がありません"
      assert_includes 3..5, entry.examples.size, "#{entry.name} の例は3〜5件にする"
    end

    # 名前で引ける(無い名前は nil)
    entry = LinguisticFeatureGlossary.find("音韻添加")
    assert_match "無い音が間に加わる", entry.description
    assert entry.examples.any? { |example| example.include?("まんなか") }
    # 定義は説明の最初の 1 文(句点まで)。句点の無い説明は全文
    assert_equal "複合語を作るとき、もとの語には無い音が間に加わる現象。", entry.definition
    assert_equal "句点の無い説明", LinguisticFeatureGlossary::Entry.new(description: "句点の無い説明").definition
    # 残り(定義に続く文)は、定義とつなぐと説明の全文に戻る。定義だけの説明には無い
    assert_equal entry.description, entry.definition + entry.supplement
    assert_nil LinguisticFeatureGlossary.find("イ音便").supplement

    assert_nil LinguisticFeatureGlossary.find("存在しない特徴")
  end
end
