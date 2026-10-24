require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# 調査データ(Claude Code 連携の入口。Issue 108)。各画面の中身は AnnotationProposalsControllerTest などで見る。
class Admin::ResearchControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(admins(:one)) }

  test "書き出し・特徴の再調査・取り込み・提案キューへ、作業の順に件数つきで案内する" do
    get admin_research_path
    assert_response :success

    assert_equal [ export_admin_annotation_proposals_path, export_features_admin_annotation_proposals_path,
                   new_admin_annotation_proposal_path, admin_annotations_path(proposed: 1) ],
                 css_select(".admin-card__link").map { |link| link["href"] }
    assert_select ".admin-card a.admin-card__sublink[href=?]", admin_bulk_proposal_approval_path
    # フィクスチャでは、未注釈 3 語のうち提案があるのは haruhi だけ
    assert_select ".admin-card__meta--pending > span", text: I18n.t("admin.research.export.meta", count: 2)
    assert_select ".admin-card__meta--pending > span", text: I18n.t("admin.research.queue.meta", count: 1)
  end
end
