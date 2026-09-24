require "test_helper"

# 拡張: 拡張待ちの語を書き出し、結果を取り込むと仕分けへ移る。
class Admin::Candidates::ExpansionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(admins(:one))
    @seed = WordCandidate.create!(surface: "泥門デビルバッツ", status: :expanding)
  end

  test "拡張待ちの語を「#ID 表層形」で書き出し、状態の名前からその語の一覧へ行ける" do
    get admin_candidates_expansion_path
    assert_response :success
    assert_select ".cand-export[data-clipboard-text-value=?]", "##{@seed.id} 泥門デビルバッツ"
    assert_select "textarea[name=expand_export]", text: "##{@seed.id} 泥門デビルバッツ"
    assert_select ".cand-export__count a[href=?]", admin_candidates_list_path(status: "expanding"),
                  text: I18n.t("admin.word_candidates.statuses.expanding")
  end

  test "結果を取り込むと、元の語と集めた語が仕分けに系統として並ぶ" do
    post import_admin_candidates_expansion_path,
         params: { json: { seeds: [ { id: @seed.id, words: [ "神龍寺ナーガ" ] } ] }.to_json }
    assert_redirected_to admin_candidates_triage_path
    assert_equal I18n.t("admin.word_candidates.import_results.seeds", count: 1) + " / " +
                 I18n.t("admin.word_candidates.import_results.created", count: 1), flash[:notice]

    follow_redirect!
    assert_select ".cand-family .cand-row", 2
  end

  test "読めない JSON は画面を出し直す" do
    post import_admin_candidates_expansion_path, params: { json: "{" }
    assert_response :unprocessable_content
    assert_select "#flash", text: /#{I18n.t("admin.word_candidates.import.invalid_json")}/
    assert_select "textarea[name=json]", text: "{"
  end
end
