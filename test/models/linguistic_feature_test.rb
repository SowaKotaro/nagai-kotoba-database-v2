require "test_helper"

# 言語学的特徴マスタ。選択肢の並び(公開側の詳細検索と管理画面で共通)。
class LinguisticFeatureTest < ActiveSupport::TestCase
  test "選択肢は用語解説の順に並び、用語解説に無い特徴は末尾に名前順で置く" do
    %w[ゴママヨ ハ行転呼 未登録の特徴イ 未登録の特徴ア].each { |name| LinguisticFeature.create!(name:) }

    assert_equal %w[連濁 ハ行転呼 重箱読み ゴママヨ 未登録の特徴ア 未登録の特徴イ],
                 LinguisticFeature.in_glossary_order.map(&:name)
  end
end
