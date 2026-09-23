require "test_helper"

class WordCandidateTest < ActiveSupport::TestCase
  test "表層形の改行を畳み、upload した時点の表記を残す" do
    candidate = WordCandidate.create!(surface: " 泥門\nデビルバッツ ")
    assert_equal "泥門 デビルバッツ", candidate.surface
    assert_predicate candidate, :upload?

    candidate.update!(surface: "泥門デビルバッツ")
    assert_equal "泥門 デビルバッツ", candidate.original_surface
  end

  test "表層形は照合順序 as_ci で一意(ひらがな⇔カタカナ違いは同じ語、清濁違いは別の語)" do
    WordCandidate.create!(surface: "はなはさくらぎ")
    assert_not WordCandidate.new(surface: "ハナハサクラギ").valid?
    assert WordCandidate.new(surface: "ばなはさくらぎ").valid?
  end

  test "状態を動かした時刻を残す" do
    candidate = WordCandidate.create!(surface: "天上天下唯我独尊")
    travel_to Time.zone.local(2026, 9, 24, 10, 0) do
      candidate.update!(status: :expand)
    end
    assert_equal Time.zone.local(2026, 9, 24, 10, 0), candidate.status_changed_at
  end

  test "一覧の並びは upload した順で、expand で増えた語は元の語の直後に来る" do
    first = WordCandidate.create!(surface: "泥門デビルバッツ")
    second = WordCandidate.create!(surface: "王城ホワイトナイツ")
    third = WordCandidate.create!(surface: "初恋クレイジー")
    child = WordCandidate.create!(surface: "神龍寺ナーガ", **first.expansion_attributes)
    grandchild = WordCandidate.create!(surface: "白秋ダイナソアーズ", **child.expansion_attributes)

    assert_equal [ first, child, grandchild, second, third ], WordCandidate.in_tree_order.to_a
    assert_equal first.id, grandchild.root_id
  end

  test "処理を当てると段を移し、段に入り直す語は取り込み済みの印を消す" do
    candidate = WordCandidate.create!(surface: "泥門デビルバッツ", status: :expand, expanded_at: Time.current, notated_at: Time.current)

    WordCandidate.apply_action!([ candidate ], "to_expand")
    candidate.reload
    assert_predicate candidate, :expand?
    assert_nil candidate.expanded_at
    assert_nil candidate.notated_at

    WordCandidate.apply_action!([ candidate ], "to_rejected")
    assert_predicate candidate.reload, :rejected?
  end

  test "一括登録で収録された語と同じ表層形の語を登録済みにする" do
    candidate = WordCandidate.create!(surface: words(:curry).surface, status: :done)
    WordCandidate.register_for!(words(:curry))

    candidate.reload
    assert_predicate candidate, :registered?
    assert_equal words(:curry), candidate.word
  end

  test "立項スコアは 1〜5、確からしさは high / medium / low だけを受け付ける" do
    assert_not WordCandidate.new(surface: "語", entry_score: 6).valid?
    assert_not WordCandidate.new(surface: "語", confidence: "sure").valid?
    assert WordCandidate.new(surface: "語", entry_score: 3, confidence: "medium").valid?
  end
end
