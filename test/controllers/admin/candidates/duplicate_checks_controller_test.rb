require "test_helper"

# duplicate の段: 一致した語を最初からチェックし、チェックした語を重複に、残りを notation へ。
class Admin::Candidates::DuplicateChecksControllerTest < ActionDispatch::IntegrationTest
  test "一致した語はチェック済みで出し、送るとチェックした語は重複、残りは notation になる" do
    sign_in_as(admins(:one))
    matched = WordCandidate.create!(surface: "カレー・ライス", status: :duplicate)
    clean = WordCandidate.create!(surface: "どこにも無い言葉", status: :duplicate)

    get admin_candidates_duplicate_check_path
    assert_response :success
    assert_select "input[name='duplicated_ids[]'][value='#{matched.id}'][checked]"
    assert_select "input[name='duplicated_ids[]'][value='#{clean.id}']:not([checked])"
    assert_select ".admin-candidates-table__matches a[href=?]", word_path(words(:curry))

    # 表示後に入ってきた語は送らない
    late = WordCandidate.create!(surface: "後から来た言葉", status: :duplicate)
    patch admin_candidates_duplicate_check_path, params: { shown_ids: [ matched.id, clean.id ], duplicated_ids: [ matched.id ] }
    assert_redirected_to admin_candidates_notation_path
    assert_equal %w[duplicated notation duplicate], [ matched, clean, late ].map { |c| c.reload.status }
  end
end
