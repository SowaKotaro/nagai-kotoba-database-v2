require "test_helper"

class WordCandidateNotationImportTest < ActiveSupport::TestCase
  def import(words)
    WordCandidateNotationImport.new({ version: "1", words: words }.to_json).call
  end

  test "表記を置き換えて取り込み済みの印を立て、立項スコア・確からしさ・メモを残す(元の表記は残る)" do
    candidate = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notation)

    result = import([ { id: candidate.id, surface: "ゴールドマン・サックス", entry_score: 5, confidence: "high", note: "中黒入り" } ])

    candidate.reload
    assert_predicate candidate, :notation?
    assert_predicate candidate.notated_at, :present?
    assert_equal "ゴールドマン・サックス", candidate.surface
    assert_equal "ゴールドマンサックス", candidate.original_surface
    assert_equal [ 5, "high", "中黒入り" ], [ candidate.entry_score, candidate.confidence, candidate.note ]
    assert_equal 1, result.counts[:renamed]
  end

  test "立項スコアが2以下の語は要判断へ回す(範囲外のスコアや未知の確からしさは捨てる)" do
    doubtful = WordCandidate.create!(surface: "とてつもなく大きな", status: :notation)
    odd = WordCandidate.create!(surface: "変なスコアの言葉", status: :notation)

    import([ { id: doubtful.id, entry_score: 2 }, { id: odd.id, entry_score: 9, confidence: "sure" } ])

    assert_predicate doubtful.reload, :pending?
    odd.reload
    assert_predicate odd, :notation?
    assert_nil odd.entry_score
    assert_nil odd.confidence
  end

  test "統一後の表記が収録済みの語やほかの登録予定単語と重なったら、表記を変えずに重複へ回す" do
    to_word = WordCandidate.create!(surface: "カレエライス", status: :notation)
    other = WordCandidate.create!(surface: "天上天下唯我独尊", status: :expand)
    to_other = WordCandidate.create!(surface: "天上天下唯我独尊(仏教語)", status: :notation)

    result = import([ { id: to_word.id, surface: "カレーライス" }, { id: to_other.id, surface: other.surface } ])

    assert_equal 2, result.counts[:duplicate]
    to_word.reload
    assert_predicate to_word, :duplicated?
    assert_equal "カレエライス", to_word.surface
    assert_includes to_word.note, "カレーライス"
    assert_predicate to_other.reload, :duplicated?
  end

  test "同じ取り込みの中で統一後の表記がぶつかった語も重複へ回す" do
    first = WordCandidate.create!(surface: "ABC 殺人", status: :notation)
    second = WordCandidate.create!(surface: "ＡＢＣ殺人", status: :notation)

    import([ { id: first.id, surface: "エービーシー殺人" }, { id: second.id, surface: "エービーシー殺人" } ])

    assert_predicate first.reload, :notation?
    assert_predicate second.reload, :duplicated?
  end

  test "分割案があれば元の語を不要にし、分割後の語を元の語の下に duplicate の段から入れ直す" do
    candidate = WordCandidate.create!(surface: "経済・経営学部", status: :notation)

    result = import([ { id: candidate.id, entry_score: 2, split: [ "経済学部", "経営学部" ] } ])

    assert_predicate candidate.reload, :rejected?
    assert_includes candidate.note, "経済学部 / 経営学部"
    assert_equal [ [ "duplicate", candidate.id ] ] * 2, WordCandidate.where(surface: %w[経済学部 経営学部]).pluck(:status, :seed_id)
    assert_equal 1, result.counts[:split]
  end

  test "取り込み済みの語は見送り、同じ JSON を2回貼っても二重に動かない" do
    candidate = WordCandidate.create!(surface: "表記の言葉", status: :notation)
    import([ { id: candidate.id, surface: "表記のことば" } ])

    result = import([ { id: candidate.id, surface: "別の表記" } ])

    assert_equal 1, result.counts[:stale]
    assert_equal "表記のことば", candidate.reload.surface
  end
end
