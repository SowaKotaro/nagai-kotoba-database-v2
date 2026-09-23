require "test_helper"

class WordCandidateIntakeTest < ActiveSupport::TestCase
  test "箇条書きの記号と重複行を除いて upload の語として入れる(収録済みの語も入れる)" do
    result = WordCandidateIntake.new(text: "1. 泥門デビルバッツ\n- #{words(:curry).surface}\n\n・泥門デビルバッツ\n").call

    assert_equal 2, result.created
    assert_equal %w[upload upload], WordCandidate.where(surface: [ "泥門デビルバッツ", words(:curry).surface ]).pluck(:status)
  end

  test "既に入っている語(不要にした語を含む)は入れ直さず、どの状態にあったかを数える" do
    WordCandidate.create!(surface: "きゃっかしたことば", status: :rejected)
    WordCandidate.create!(surface: "選別中の言葉", status: :expand)

    # ひらがな⇔カタカナ違いも同じ語(照合順序 as_ci)
    result = WordCandidateIntake.new(text: "キャッカシタコトバ\n選別中の言葉").call

    assert_equal 0, result.created
    assert_equal({ "rejected" => 1, "expand" => 1 }, result.existing)
  end

  test "入れられなかった行はエラーとして返し、他の行は入れる" do
    result = WordCandidateIntake.new(text: "#{'長' * 256}\n正常な言葉").call

    assert_equal 1, result.created
    assert_equal 1, result.errors.size
  end

  test "行数の上限を超えたかを判定する" do
    text = (1..(WordCandidateIntake::MAX_LINES + 1)).map { |i| "語#{i}" }.join("\n")
    assert WordCandidateIntake.new(text: text).too_many?
  end
end
