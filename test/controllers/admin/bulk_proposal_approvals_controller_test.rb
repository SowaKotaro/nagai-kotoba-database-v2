require "test_helper"

# 提案の一括承認(Issue 65)。プレビュー(show)と承認(create)。
class Admin::BulkProposalApprovalsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(admins(:one)) }

  test "プレビューは対象語と承認ボタンを出し、対象が無ければ空表示" do
    get admin_bulk_proposal_approval_path
    assert_response :success
    assert_select ".bulk-approval__word", text: /涼宮ハルヒの憂鬱/
    assert_select "input[type=submit]"

    # 対象が無ければ空表示で承認ボタンを出さない
    annotation_proposals(:haruhi_proposal).applied!
    get admin_bulk_proposal_approval_path
    assert_response :success
    assert_select ".bulk-approval", count: 0
    assert_select "input[type=submit]", count: 0
  end

  test "一括承認すると対象語が公開され、提案が applied、提案キューへ戻る" do
    assert_changes -> { words(:pending_haruhi).reload.annotated_at }, from: nil do
      post admin_bulk_proposal_approval_path
    end
    assert annotation_proposals(:haruhi_proposal).reload.applied?
    assert_redirected_to admin_annotations_path(proposed: 1)
  end
end
