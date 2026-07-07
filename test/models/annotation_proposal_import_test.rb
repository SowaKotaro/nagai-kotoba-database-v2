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

  test "壊れた JSON・形式違いは nil を返す" do
    assert_nil AnnotationProposalImport.new("{ 壊れた").import
    assert_nil AnnotationProposalImport.new({ words: [] }.to_json).import
  end
end
