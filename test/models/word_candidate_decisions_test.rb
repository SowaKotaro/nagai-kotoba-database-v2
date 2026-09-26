require "test_helper"

class WordCandidateDecisionsTest < ActiveSupport::TestCase
  TRIAGE_CHOICES = WordCandidateReview::CHOICES[:triage]

  def decide(decisions, statuses: %w[triage held], choices: TRIAGE_CHOICES)
    WordCandidateDecisions.new(decisions.transform_keys { |candidate| candidate.id.to_s }, statuses: statuses, choices: choices).call
  end

  test "語ごとに選んだ処理の行き先へ移し、移した先ごとの語数を返す(保留のままの語は数えない)" do
    seed = WordCandidate.create!(surface: "泥門デビルバッツ")
    keep = WordCandidate.create!(surface: "天上天下唯我独尊")
    notated = WordCandidate.create!(surface: "確かめた言葉", status: :held, notated_at: Time.current)
    still = WordCandidate.create!(surface: "迷っている言葉", status: :held)
    unwanted = WordCandidate.create!(surface: "要らない言葉")

    counts = decide({ seed => "expand", keep => "keep", notated => "keep", still => "hold", unwanted => "reject" })

    assert_equal %w[expanding notating ready held rejected], [ seed, keep, notated, still, unwanted ].map { |c| c.reload.status }
    assert_equal({ "expanding" => 1, "notating" => 1, "ready" => 1, "rejected" => 1 }, counts)
  end

  test "除外した語が照合で一致すれば重複にし、相手をメモに残す" do
    candidate = WordCandidate.create!(surface: "カレー・ライス", note: "調査の注記")

    decide({ candidate => "reject" })

    candidate.reload
    assert_predicate candidate, :duplicated?
    assert_equal "調査の注記 / #{I18n.t("admin.word_candidates.duplicate_note", other: words(:curry).surface)}", candidate.note
  end

  test "画面に並べたステータスにいない語と、その画面で選べない処理は動かさない" do
    moved = WordCandidate.create!(surface: "ほかの画面で動かした言葉", status: :notating)
    notated = WordCandidate.create!(surface: "確かめ中の言葉", status: :notated)

    counts = decide({ moved => "reject", notated => "expand" }, statuses: %w[notated], choices: WordCandidateReview::CHOICES[:notation])

    assert_empty counts
    assert_equal %w[notating notated], [ moved, notated ].map { |c| c.reload.status }
  end
end
