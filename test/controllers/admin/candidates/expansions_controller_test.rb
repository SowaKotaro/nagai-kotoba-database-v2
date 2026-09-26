require "test_helper"

# 拡張: 拡張待ちの語を(数十語ずつ)書き出し、結果を取り込むと仕分けへ移る。
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

  test "一度に渡す語数を指定して、拡張待ちの先頭からその語数だけを書き出す(既定は 30 語)" do
    waiting = (1..30).map { |i| WordCandidate.create!(surface: "拡張を待つ言葉#{i}", status: :expanding) }

    get admin_candidates_expansion_path
    assert_select "input[name=limit][value=?]", "30"
    assert_select ".cand-export__count", text: /31 語のうち、先頭の\s*30\s*語/
    assert_select "textarea[name=expand_export]", text: /\A##{@seed.id} 泥門デビルバッツ\n.*##{waiting[28].id} 拡張を待つ言葉29\z/m

    get admin_candidates_expansion_path(limit: 2)
    assert_select "textarea[name=expand_export]", text: "##{@seed.id} 泥門デビルバッツ\n##{waiting[0].id} 拡張を待つ言葉1"
    # 読めない JSON で出し直しても、指定した語数を保つ
    assert_select "form[action=?]", import_admin_candidates_expansion_path(limit: 2)
  end

  test "書き出した語だけを取り込むと、残りは拡張待ちに残り、残りの語数を知らせる" do
    rest = WordCandidate.create!(surface: "次の回に渡す言葉", status: :expanding)

    post import_admin_candidates_expansion_path, params: { json: { seeds: [ { id: @seed.id, words: [] } ] }.to_json }

    assert_equal %w[triage expanding], [ @seed.reload.status, rest.reload.status ]
    assert_equal I18n.t("admin.word_candidates.import_results.seeds", count: 1) + " / " +
                 I18n.t("admin.word_candidates.import_results.remaining", status: "拡張待ち", count: 1), flash[:notice]
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
