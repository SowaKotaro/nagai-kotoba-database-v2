require "test_helper"

class WordCandidateExportTest < ActiveSupport::TestCase
  test "その段でまだ結果を取り込んでいない語を「#ID 表層形」で書き出す(expand で増えた語は含めない)" do
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", status: :expand)
    WordCandidate.create!(surface: "取り込み済みの言葉", status: :expand, expanded_at: Time.current)
    WordCandidate.create!(surface: "増えた言葉", status: :expand, expanded_at: Time.current, **seed.expansion_attributes)
    notation = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notation)

    assert_equal "##{seed.id} 泥門デビルバッツ", WordCandidateExport.new("expand").text
    assert_equal "##{notation.id} ゴールドマンサックス", WordCandidateExport.new("notation").text
  end
end
