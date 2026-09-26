require "test_helper"

class WordCandidateTest < ActiveSupport::TestCase
  test "表層形の改行を畳み、入った時点の表記を残す(はじめは仕分け待ち)" do
    candidate = WordCandidate.create!(surface: " 泥門\nデビルバッツ ")
    assert_equal "泥門 デビルバッツ", candidate.surface
    assert_predicate candidate, :triage?

    candidate.update!(surface: "泥門デビルバッツ")
    assert_equal "泥門 デビルバッツ", candidate.original_surface
    assert_predicate candidate, :surface_changed_since_intake?
  end

  test "表層形は照合順序 as_ci で一意(ひらがな⇔カタカナ違いは同じ語、清濁違いは別の語)" do
    WordCandidate.create!(surface: "はなはさくらぎ")
    assert_not WordCandidate.new(surface: "ハナハサクラギ").valid?
    assert WordCandidate.new(surface: "ばなはさくらぎ").valid?
  end

  test "状態を動かした時刻を残す" do
    candidate = WordCandidate.create!(surface: "天上天下唯我独尊")
    travel_to Time.zone.local(2026, 9, 24, 10, 0) do
      candidate.update!(status: :expanding)
    end
    assert_equal Time.zone.local(2026, 9, 24, 10, 0), candidate.status_changed_at
  end

  test "並びは入った順で、expand で増えた語は元の語の直後に来る" do
    first = WordCandidate.create!(surface: "泥門デビルバッツ")
    second = WordCandidate.create!(surface: "王城ホワイトナイツ")
    third = WordCandidate.create!(surface: "初恋クレイジー")
    child = WordCandidate.create!(surface: "神龍寺ナーガ", **first.expansion_attributes)
    grandchild = WordCandidate.create!(surface: "白秋ダイナソアーズ", **child.expansion_attributes)

    assert_equal [ first, child, grandchild, second, third ], WordCandidate.in_tree_order.to_a
    assert_equal first.id, grandchild.root_id
  end

  test "選んだ処理の行き先: 採用は表記を確かめ済みなら登録待ち、まだなら表記待ち。除外は一致があれば重複" do
    fresh = WordCandidate.new(surface: "新しい言葉")
    notated = WordCandidate.new(surface: "確かめた言葉", notated_at: Time.current)

    assert_equal "expanding", fresh.destination_for("expand")
    assert_equal "notating", fresh.destination_for("keep")
    assert_equal "ready", notated.destination_for("keep")
    assert_equal "held", fresh.destination_for("hold")
    assert_equal "rejected", fresh.destination_for("reject")
    assert_equal "duplicated", fresh.destination_for("reject", duplicate: true)
    assert_nil fresh.destination_for("registered")
  end

  test "立項スコアが2以下の語は立項に疑義がある" do
    assert_predicate WordCandidate.new(entry_score: 2), :doubtful_entry?
    assert_not_predicate WordCandidate.new(entry_score: 3), :doubtful_entry?
    assert_not_predicate WordCandidate.new, :doubtful_entry?
  end

  test "表層形の部分一致で探せる(元の表記も対象。LIKE の記号は文字として扱う)" do
    renamed = WordCandidate.create!(surface: "ゴールドマンサックス")
    renamed.update!(surface: "ゴールドマン・サックス")
    percent = WordCandidate.create!(surface: "100%の言葉")

    assert_equal [ renamed ], WordCandidate.matching("マンサック").to_a
    assert_equal [ percent ], WordCandidate.matching("%").to_a
  end

  test "一括登録で収録された語と同じ表層形の語を登録済みにする" do
    candidate = WordCandidate.create!(surface: words(:curry).surface, status: :ready)
    WordCandidate.register_for!(words(:curry))

    candidate.reload
    assert_predicate candidate, :registered?
    assert_equal words(:curry), candidate.word
  end

  test "入れられなかった理由: 検証エラーは訳した内容、一意制約の違反は先頭 191 字がほかの語と同じこと" do
    invalid = assert_raises(ActiveRecord::RecordInvalid) { WordCandidate.create!(surface: "長" * 256, entry_score: 9) }
    assert_equal "表層形 は255文字以内で入力してください、立項スコア は1..5の範囲に含めてください",
                 WordCandidate.save_error_message(invalid)

    WordCandidate.create!(surface: "#{'長' * 191}い")
    not_unique = assert_raises(ActiveRecord::RecordNotUnique) { WordCandidate.create!(surface: "#{'長' * 191}う") }
    assert_equal I18n.t("admin.word_candidates.not_unique"), WordCandidate.save_error_message(not_unique)
  end

  test "立項スコアは 1〜5、確からしさは high / medium / low だけを受け付ける" do
    assert_not WordCandidate.new(surface: "語", entry_score: 6).valid?
    assert_not WordCandidate.new(surface: "語", confidence: "sure").valid?
    assert WordCandidate.new(surface: "語", entry_score: 3, confidence: "medium").valid?
  end
end
