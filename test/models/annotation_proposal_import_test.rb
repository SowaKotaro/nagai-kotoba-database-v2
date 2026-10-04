require "test_helper"

# 提案 JSON の取り込み(Issue 38)。語ごとに1件・再貼り付けは上書き(冪等)。
class AnnotationProposalImportTest < ActiveSupport::TestCase
  def import_json(proposals)
    AnnotationProposalImport.new({ version: "1", proposals: proposals }.to_json).import
  end

  test "提案を pending の下書きとして保存する" do
    bermuda = words(:pending_bermuda)

    assert_difference -> { AnnotationProposal.count }, 1 do
      result = import_json([ { word_id: bermuda.id, meaning: "大西洋の海域。", confidence: "high" } ])
      assert_equal 1, result.saved
      assert_empty result.unknown_word_ids
    end

    proposal = bermuda.reload.annotation_proposal
    assert proposal.pending?
    assert_equal "大西洋の海域。", proposal.meaning
  end

  test "同じ語への再取り込みは上書きして pending に戻す(冪等)" do
    existing = annotation_proposals(:haruhi_proposal)
    existing.applied!

    assert_no_difference -> { AnnotationProposal.count } do
      import_json([ { word_id: existing.word_id, meaning: "上書き後の意味。" } ])
    end

    existing.reload
    assert existing.pending?
    assert_equal "上書き後の意味。", existing.meaning
  end

  test "存在しない word_id は取り込まずに知らせる" do
    result = import_json([
      { word_id: words(:pending_bermuda).id, meaning: "取り込まれる。" },
      { word_id: 999_999, meaning: "取り込まれない。" }
    ])

    assert_equal 1, result.saved
    assert_equal [ 999_999 ], result.unknown_word_ids
  end

  test "想定外のキーは payload に取り込まない" do
    import_json([ { word_id: words(:pending_bermuda).id, meaning: "意味。", evil: "余計なデータ" } ])
    assert_nil words(:pending_bermuda).reload.annotation_proposal.payload["evil"]
  end

  # 選別するのはトップレベルのキーだけ(AnnotationProposal::PAYLOAD_KEYS)。旧形式の reading と
  # linguistic_features は保持しない。
  test "トップレベルの reading・linguistic_features・sense_id は捨て、旧形式の語義の読みと特徴は空になる" do
    import_json([ {
      word_id: words(:pending_bermuda).id, meaning: "大西洋の海域。", reading: "バミューダトライアングル",
      linguistic_features: [ { name: "連濁", target: "バミューダ", target_reading: "バミューダ" } ], sense_id: 123
    } ])

    proposal = words(:pending_bermuda).reload.annotation_proposal
    assert_equal %w[meaning], proposal.payload.keys
    assert_nil proposal.senses.first.reading
    assert_empty proposal.senses.first.linguistic_features
  end

  test "senses の要素は中身を丸ごと保持する(genre_new・target_start・未知のキーも残る)" do
    sense = { meaning: "意味。", genre_new: true, extra_in_sense: "残る",
              linguistic_features: [ { name: "連濁", target: "トライアングル", target_reading: "トライアングル", target_start: 5 } ] }
    import_json([ { word_id: words(:pending_bermuda).id, genre_new: true, senses: [ sense ] } ])

    payload = words(:pending_bermuda).reload.annotation_proposal.payload
    assert_equal true, payload["genre_new"]
    assert_equal sense.deep_stringify_keys, payload["senses"].first
  end

  test "立項スコアと懸念理由を保持する(Issue 39)" do
    import_json([ {
      word_id: words(:pending_bermuda).id, entry_score: 2, entry_notes: "公然性を欠く。"
    } ])

    proposal = words(:pending_bermuda).reload.annotation_proposal
    assert_equal 2, proposal.entry_score
    assert_equal "公然性を欠く。", proposal.entry_notes
    assert proposal.entry_concern?
  end

  test "壊れた JSON・形式違いは nil を返す" do
    assert_nil AnnotationProposalImport.new("{ 壊れた").import
    assert_nil AnnotationProposalImport.new({ words: [] }.to_json).import
  end
end
