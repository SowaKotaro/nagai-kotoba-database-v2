require "test_helper"

# 表記: 書き出し → 結果の取り込み → 語ごとに確かめて確定すると登録待ちへ。
class Admin::Candidates::NotationsControllerTest < ActionDispatch::IntegrationTest
  test "結果を取り込むと確かめる一覧に並び、確定すると採用した語が登録待ちになる" do
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notating)
    doubtful = WordCandidate.create!(surface: "とてつもなく大きな", status: :notating)

    get admin_candidates_notation_path
    assert_select "textarea[name=notation_export]", text: "##{candidate.id} ゴールドマンサックス\n##{doubtful.id} とてつもなく大きな"

    post import_admin_candidates_notation_path, params: { json: { words: [
      { id: candidate.id, surface: "ゴールドマン・サックス", entry_score: 5 }, { id: doubtful.id, entry_score: 1 }
    ] }.to_json }
    assert_redirected_to admin_candidates_notation_path(anchor: "review")

    follow_redirect!
    assert_select "input[name='decisions[#{candidate.id}]'][value=keep][checked]"
    assert_select "input[name='decisions[#{doubtful.id}]'][value=hold][checked]"
    # 表記の確認では拡張を選べない
    assert_select "input[name='decisions[#{candidate.id}]'][value=expand]", 0
    assert_select ".cand-filter__chip[data-flag=changed]", text: /1/
    assert_select ".cand-filter__chip[data-flag=doubtful]", text: /1/

    patch admin_candidates_notation_path, params: { decisions: { candidate.id => "keep", doubtful.id => "hold" } }
    assert_redirected_to admin_candidates_registration_path
    assert_equal %w[ready held], [ candidate.reload.status, doubtful.reload.status ]
  end
end
