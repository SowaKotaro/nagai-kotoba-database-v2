require "test_helper"

# expand の段: 書き出し → 結果の取り込み → 取り込み済みの語を duplicate へ。
class Admin::Candidates::ExpansionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(admins(:one))
    @seed = WordCandidate.create!(surface: "泥門デビルバッツ", status: :expand)
  end

  test "まだ結果の無い語を「#ID 表層形」で書き出す" do
    get admin_candidates_expansion_path
    assert_response :success
    assert_select "textarea[name=expand_input]", text: "##{@seed.id} 泥門デビルバッツ"
  end

  test "結果を取り込むと増えた語が元の語の下に並び、まとめて duplicate へ送れる(結果の無い語は残る)" do
    waiting = WordCandidate.create!(surface: "初恋クレイジー", status: :expand)
    post import_admin_candidates_expansion_path,
         params: { json: { seeds: [ { id: @seed.id, words: [ "神龍寺ナーガ" ] } ] }.to_json }
    assert_redirected_to admin_candidates_expansion_path
    follow_redirect!
    assert_select ".candidate-tree li", 2
    assert_select ".candidate-tree .candidate-surface__branch", text: "↳"

    patch admin_candidates_expansion_path
    assert_redirected_to admin_candidates_duplicate_check_path
    assert_equal 2, WordCandidate.duplicate.count
    assert_predicate waiting.reload, :expand?
  end

  test "読めない JSON は画面を出し直す" do
    post import_admin_candidates_expansion_path, params: { json: "{" }
    assert_response :unprocessable_content
    assert_select ".form-alert", text: I18n.t("admin.word_candidates.import.invalid_json")
  end
end
