require "test_helper"

class WordCandidateNotationImportTest < ActiveSupport::TestCase
  def import(words)
    WordCandidateNotationImport.new({ version: "1", words: words }.to_json).call
  end

  test "表記を置き換えて表記の確認待ちにし、立項スコア・確からしさ・メモを残す(元の表記は残る)" do
    candidate = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notating)

    result = import([ { id: candidate.id, surface: "ゴールドマン・サックス", entry_score: 5, confidence: "high", note: "中黒入り" } ])

    candidate.reload
    assert_predicate candidate, :notated?
    assert_predicate candidate.notated_at, :present?
    assert_equal "ゴールドマン・サックス", candidate.surface
    assert_equal "ゴールドマンサックス", candidate.original_surface
    assert_equal [ 5, "high", "中黒入り" ], [ candidate.entry_score, candidate.confidence, candidate.note ]
    assert_equal [ 1, 1 ], result.counts.values_at(:notated, :renamed)
  end

  test "立項スコアが低い語・収録済みの語と重なった語も振り分けずに確認待ちにする(範囲外のスコアや未知の確からしさは捨てる)" do
    doubtful = WordCandidate.create!(surface: "とてつもなく大きな", status: :notating)
    to_word = WordCandidate.create!(surface: "カレエライス", status: :notating)
    odd = WordCandidate.create!(surface: "変なスコアの言葉", status: :notating)

    result = import([ { id: doubtful.id, entry_score: 2 }, { id: to_word.id, surface: "カレーライス" },
                      { id: odd.id, entry_score: 9, confidence: "sure" } ])

    assert_equal %w[notated notated notated], [ doubtful, to_word, odd ].map { |c| c.reload.status }
    assert_equal "カレーライス", to_word.surface
    assert_nil odd.entry_score
    assert_nil odd.confidence
    assert_equal 1, result.counts[:doubtful]
  end

  test "統一後の表記がほかの登録予定単語とまったく同じになった語は、表記を変えずに重複にする" do
    other = WordCandidate.create!(surface: "天上天下唯我独尊", status: :expanding)
    collided = WordCandidate.create!(surface: "天上天下唯我独尊(仏教語)", status: :notating)
    first = WordCandidate.create!(surface: "ABC 殺人", status: :notating)
    second = WordCandidate.create!(surface: "ＡＢＣ殺人", status: :notating)

    result = import([ { id: collided.id, surface: other.surface },
                      { id: first.id, surface: "エービーシー殺人" }, { id: second.id, surface: "エービーシー殺人" } ])

    collided.reload
    assert_predicate collided, :duplicated?
    assert_equal "天上天下唯我独尊(仏教語)", collided.surface
    assert_includes collided.note, "天上天下唯我独尊"
    assert_predicate first.reload, :notated?
    assert_predicate second.reload, :duplicated?
    assert_equal 2, result.counts[:collided]
  end

  test "分割案があれば元の語を不要にし、分割後の語を元の語の系統として仕分けに入れ直す" do
    candidate = WordCandidate.create!(surface: "経済・経営学部", status: :notating)

    result = import([ { id: candidate.id, entry_score: 2, split: [ "経済学部", "経営学部" ] } ])

    assert_predicate candidate.reload, :rejected?
    assert_includes candidate.note, "経済学部 / 経営学部"
    assert_equal [ [ "triage", candidate.id ] ] * 2, WordCandidate.where(surface: %w[経済学部 経営学部]).pluck(:status, :seed_id)
    assert_equal [ 1, 2 ], result.counts.values_at(:split, :created)
  end

  test "入れられない語(長すぎる表記・分割後の語)はその語だけを表記待ちに残して行のエラーにし、ほかの語は取り込む" do
    too_long = WordCandidate.create!(surface: "長すぎる表記になる言葉", status: :notating)
    bad_split = WordCandidate.create!(surface: "分割に失敗する言葉", status: :notating)
    fine = WordCandidate.create!(surface: "ふつうの言葉", status: :notating)

    result = import([ { id: too_long.id, input: too_long.surface, surface: "長" * 256 },
                      { id: bad_split.id, input: bad_split.surface, split: [ "分割した語", "長" * 256 ] },
                      { id: fine.id, surface: "普通の言葉" } ])

    assert_equal %w[notating notating notated], [ too_long, bad_split, fine ].map { |c| c.reload.status }
    # 分割は1語目を入れたあとで失敗しても、入れた語ごと戻す(件数も数えない)
    assert_not WordCandidate.exists?(surface: "分割した語")
    assert_equal [ 2, 0, 1 ], result.counts.values_at(:errors, :created, :notated)
    assert_equal 2, result.messages.size
    assert_match(/\A##{too_long.id} 長すぎる表記になる言葉: 表層形 は255文字以内/, result.messages.first)
  end

  test "表記待ちにいない語は見送り、同じ JSON を2回貼っても二重に動かない" do
    candidate = WordCandidate.create!(surface: "表記の言葉", status: :notating)
    import([ { id: candidate.id, surface: "表記のことば" } ])

    result = import([ { id: candidate.id, surface: "別の表記" } ])

    assert_equal 1, result.counts[:stale]
    assert_equal "表記のことば", candidate.reload.surface
  end
end
