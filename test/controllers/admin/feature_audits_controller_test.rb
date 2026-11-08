require "test_helper"

# 言語学的特徴の点検(Issue 109)。書き出し(show)→ 点検結果の確認(preview)→ 選んだ行の適用(apply)。
# 行の検証と適用の規則は FeatureAuditImportTest で見る。
class Admin::FeatureAuditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(admins(:one))
    @word = create_published_word(surface: "手紙の書き方", reading: "テガミノカキカタ")
    @sense = @word.word_senses.first
  end

  def result_json(*changes)
    { "version" => "1", "task" => "linguistic_features_audit", "changes" => changes }.to_json
  end

  def addition(target: "手紙", target_reading: "テガミ")
    { "action" => "add", "word_id" => @word.id, "sense_id" => @sense.id, "name" => "連濁",
      "target" => target, "target_reading" => target_reading, "reason" => "紙の連濁" }
  end

  test "書き出しは点検する特徴を選ばせ、公開済みの語をコピー欄と JSON ファイルで渡し、結果の貼り付け欄を置く" do
    get admin_feature_audit_path(features: [ "連濁" ], from_id: @word.id, to_id: @word.id)
    assert_response :success

    assert_select "input[type=checkbox][name='features[]'][value=?][checked]", "連濁"
    assert_select "input[type=checkbox][name='features[]'][value=?]:not([checked])", "重箱読み"
    exported = JSON.parse(css_select("textarea#export_json").first.text)
    assert_equal [ "連濁" ], exported["features_to_check"]
    assert_equal [ @word.id ], exported["words"].map { |word| word["word_id"] }
    # 確認の画面は 200 で描くので、Turbo を通すと応答が捨てられて画面が変わらない
    assert_select "form[action=?][data-turbo=false] textarea[name=result_json]", preview_admin_feature_audit_path

    get admin_feature_audit_path(format: :json, from_id: @word.id, to_id: @word.id)
    assert_response :success
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_match "feature-audit-#{@word.id}-#{@word.id}.json", response.headers["Content-Disposition"]
    assert_equal [ @word.id ], JSON.parse(response.body)["words"].map { |word| word["word_id"] }
  end

  test "確認の画面は、適用できる行だけを選ばせ、問題のある行は理由を出して選べなくする。読めない JSON は書き出しの画面でエラー" do
    post preview_admin_feature_audit_path, params: { result_json: result_json(addition, addition(target: "葉書")) }
    assert_response :success

    assert_select "form[action=?] input[type=hidden][name=result_json]", apply_admin_feature_audit_path
    assert_select "input[name='selected[]'][value='0'][checked]:not([disabled])"
    assert_select "input[name='selected[]'][value='1'][disabled]:not([checked])"
    assert_select "td", text: I18n.t("admin.feature_audits.problems.target_not_in_surface")
    assert_select ".bulk-approval__word a[href=?]", edit_admin_word_path(@word)

    post preview_admin_feature_audit_path, params: { result_json: "読めない" }
    assert_response :unprocessable_content
    assert_select "#flash", text: /#{Regexp.escape(I18n.t("admin.feature_audits.parse_error"))}/
  end

  test "適用すると選んだ行の特徴だけが付き、書き出しの画面へ件数を添えて戻る" do
    assert_difference -> { @sense.word_sense_features.count }, 1 do
      post apply_admin_feature_audit_path, params: { result_json: result_json(addition), selected: [ "0" ] }
    end
    assert_redirected_to admin_feature_audit_path
    assert_equal I18n.t("admin.feature_audits.applied", added: 1, removed: 0, words: 1), flash[:notice]

    post apply_admin_feature_audit_path, params: { result_json: "読めない" }
    assert_redirected_to admin_feature_audit_path
    assert_equal I18n.t("admin.feature_audits.parse_error"), flash[:alert]
  end
end
