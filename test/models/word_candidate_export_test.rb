require "test_helper"

class WordCandidateExportTest < ActiveSupport::TestCase
  test "その段でスキルの結果を待っている語を書き出す(/expand・/notation は「#ID 表層形」、/reading は表層形だけ)" do
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", status: :expanding)
    WordCandidate.create!(surface: "仕分け待ちの言葉")
    notating = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notating)
    WordCandidate.create!(surface: "確かめ中の言葉", status: :notated)
    WordCandidate.create!(surface: "登録待ちの言葉", status: :ready)

    assert_equal "##{seed.id} 泥門デビルバッツ", WordCandidateExport.new("expand").text
    assert_equal "##{notating.id} ゴールドマンサックス", WordCandidateExport.new("notation").text
    assert_equal "登録待ちの言葉", WordCandidateExport.new("reading").text
  end
end
