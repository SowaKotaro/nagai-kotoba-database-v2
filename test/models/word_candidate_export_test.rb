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

  test "limit を渡すと待っている語の先頭からその語数だけを書き出し、待っている語の総数も分かる" do
    first, second, _third = %w[一番目の言葉 二番目の言葉 三番目の言葉].map { |surface| WordCandidate.create!(surface: surface, status: :expanding) }

    limited = WordCandidateExport.new("expand", limit: 2)
    assert_equal "##{first.id} 一番目の言葉\n##{second.id} 二番目の言葉", limited.text
    assert_equal 3, limited.total_count
    assert_predicate limited, :limited?

    # 待っている語が limit 以下なら、すべてを書き出す(絞っていない扱い)
    assert_not_predicate WordCandidateExport.new("expand", limit: 3), :limited?
    assert_equal 3, WordCandidateExport.new("expand").total_count
  end
end
