require "test_helper"

# すべての語: 状態で絞り込み・表層形で探し、選んだ語をまとめて仕分けに戻す・保留・不要にする。
class Admin::Candidates::ListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(admins(:one))
  end

  test "状態で絞り込み、表層形で探せる" do
    rejected = WordCandidate.create!(surface: "不要にした言葉", status: :rejected)
    WordCandidate.create!(surface: "仕分け待ちの言葉")

    get admin_candidates_list_path(status: "rejected")
    assert_response :success
    assert_select ".cand-table tbody tr", 1
    assert_select ".cand-table a[href=?]", admin_word_candidate_path(rejected)

    get admin_candidates_list_path(q: "仕分け")
    assert_select ".cand-table tbody tr", 1
    assert_select ".cand-table a", text: "仕分け待ちの言葉"
  end

  test "選んだ語を移す。登録済みの語は動かさず、移す先か語が選ばれていなければ知らせる" do
    rejected = WordCandidate.create!(surface: "不要にした言葉", status: :rejected)
    registered = WordCandidate.create!(surface: words(:curry).surface, status: :registered)

    patch admin_candidates_list_path, params: { move: "triage", candidate_ids: [ rejected.id, registered.id ], status: "rejected" }
    assert_redirected_to admin_candidates_list_path(status: "rejected")
    assert_equal %w[triage registered], [ rejected.reload.status, registered.reload.status ]

    patch admin_candidates_list_path, params: { move: "registered", candidate_ids: [ rejected.id ] }
    assert_equal I18n.t("admin.candidates.lists.update.no_move"), flash[:alert]
    patch admin_candidates_list_path, params: { move: "rejected" }
    assert_equal I18n.t("admin.candidates.lists.update.no_selection"), flash[:alert]
    assert_predicate rejected.reload, :triage?
  end
end
