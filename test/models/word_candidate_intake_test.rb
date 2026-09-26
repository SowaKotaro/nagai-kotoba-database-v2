require "test_helper"

class WordCandidateIntakeTest < ActiveSupport::TestCase
  test "箇条書きの記号と重複行を除いて仕分け待ちの語として入れる(収録済みの語も入れる)" do
    result = WordCandidateIntake.new(text: "1. 泥門デビルバッツ\n- #{words(:curry).surface}\n\n・泥門デビルバッツ\n").call

    assert_equal 2, result.created
    assert_equal %w[triage triage], WordCandidate.where(surface: [ "泥門デビルバッツ", words(:curry).surface ]).pluck(:status)
  end

  test "既に入っている語(不要にした語を含む)は入れ直さず、どの状態にあったかを数える" do
    WordCandidate.create!(surface: "きゃっかしたことば", status: :rejected)
    WordCandidate.create!(surface: "選別中の言葉", status: :expanding)

    # ひらがな⇔カタカナ違いも同じ語(照合順序 as_ci)
    result = WordCandidateIntake.new(text: "キャッカシタコトバ\n選別中の言葉").call

    assert_equal 0, result.created
    assert_equal({ "rejected" => 1, "expanding" => 1 }, result.existing)
  end

  test "入れられなかった行(検証エラー・先頭 191 字だけが既存の語と同じ長い語)は理由を添えてエラーにし、他の行は入れる" do
    WordCandidate.create!(surface: "#{'長' * 191}い")

    result = WordCandidateIntake.new(text: "#{'長' * 256}\n#{'長' * 191}う\n正常な言葉").call

    assert_equal 1, result.created
    assert_equal 2, result.errors.size
    assert result.errors.first.start_with?("#{'長' * 256}: ")
    assert_equal "#{'長' * 191}う: #{I18n.t('admin.word_candidates.not_unique')}", result.errors.last
  end

  test "行数の上限を超えたかを判定する" do
    text = (1..(WordCandidateIntake::MAX_LINES + 1)).map { |i| "語#{i}" }.join("\n")
    assert WordCandidateIntake.new(text: text).too_many?
  end
end
