require "test_helper"

# 言語学的特徴の用語解説(Issue 39)。config/linguistic_features_glossary.yml が単一ソース。
class LinguisticFeatureGlossaryTest < ActiveSupport::TestCase
  test "seed のマスタ名と1対1で対応する" do
    seed_names = File.read(Rails.root.join("db/seeds/linguistic_features.rb"))
                     .scan(/^\s*"([^"]+)"/).flatten
    assert seed_names.any?, "seed から特徴名を読み取れませんでした"
    assert_equal seed_names.sort, LinguisticFeatureGlossary.all.map(&:name).sort
  end

  test "全項目に説明と3〜5件の具体例がある" do
    LinguisticFeatureGlossary.all.each do |entry|
      assert entry.description.present?, "#{entry.name} の説明がありません"
      assert_includes 3..5, entry.examples.size, "#{entry.name} の例は3〜5件にする"
    end
  end

  test "名前で引ける(無い名前は nil)" do
    entry = LinguisticFeatureGlossary.find("音韻添加")
    assert_match "無い音が間に加わる", entry.description
    assert entry.examples.any? { |example| example.include?("まんなか") }

    assert_nil LinguisticFeatureGlossary.find("存在しない特徴")
  end
end
