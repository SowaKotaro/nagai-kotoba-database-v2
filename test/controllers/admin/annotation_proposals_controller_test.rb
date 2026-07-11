require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::AnnotationProposalsControllerTest < ActionDispatch::IntegrationTest
  # --- 認可: 未認証は弾く ---
  test "未認証だと書き出し・取り込みはログインへリダイレクト" do
    get export_admin_annotation_proposals_path
    assert_redirected_to new_session_path

    get new_admin_annotation_proposal_path
    assert_redirected_to new_session_path

    assert_no_difference -> { AnnotationProposal.count } do
      post admin_annotation_proposals_path, params: { proposals_json: "{}" }
    end
    assert_redirected_to new_session_path
  end

  # --- 書き出し ---
  test "未注釈で提案が無い語とマスタ一覧を JSON で書き出す" do
    sign_in_as(Admin.take)
    get export_admin_annotation_proposals_path
    assert_response :success

    json = css_select("textarea#export_json").first.text
    data = JSON.parse(json)
    # 提案がまだ無い未注釈語(bermuda)は入り、提案済み(haruhi)と注釈済み(abc_murder)は入らない
    ids = data["words"].map { |w| w["word_id"] }
    assert_includes ids, words(:pending_bermuda).id
    assert_not_includes ids, words(:pending_haruhi).id
    assert_not_includes ids, words(:abc_murder).id
    assert_includes data["masters"]["genres"], %w[文学 日本文学 小説]
  end

  test "書き出し件数を指定できる(上限あり)" do
    sign_in_as(Admin.take)
    get export_admin_annotation_proposals_path(limit: 1)
    assert_response :success
    assert_equal 1, JSON.parse(css_select("textarea#export_json").first.text)["words"].size

    # 上限(200)を超える指定は丸める
    get export_admin_annotation_proposals_path(limit: 99_999)
    assert_response :success
  end

  test "語ID範囲を指定すると、下書き提案がある語も再調査用に書き出す" do
    sign_in_as(Admin.take)
    haruhi = words(:pending_haruhi) # 提案済み(既定の書き出しには入らない)

    get export_admin_annotation_proposals_path(from_id: haruhi.id, to_id: haruhi.id)
    assert_response :success

    ids = JSON.parse(css_select("textarea#export_json").first.text)["words"].map { |w| w["word_id"] }
    assert_includes ids, haruhi.id
  end

  test "語ID範囲を指定しても注釈済みの語は書き出さない" do
    sign_in_as(Admin.take)
    annotated = words(:abc_murder) # 注釈済み

    get export_admin_annotation_proposals_path(from_id: annotated.id, to_id: annotated.id)
    assert_response :success

    # 注釈済みしか居ない範囲なので書き出し対象は 0 語(textarea は出ない)
    assert_select "textarea#export_json", false
  end

  # --- 取り込み ---
  test "提案 JSON を下書きとして保存できる" do
    sign_in_as(Admin.take)
    json = { version: "1", proposals: [
      { word_id: words(:pending_bermuda).id, meaning: "大西洋の海域。", confidence: "high" }
    ] }.to_json

    assert_difference -> { AnnotationProposal.count }, 1 do
      post admin_annotation_proposals_path, params: { proposals_json: json }
    end
    assert_redirected_to new_admin_annotation_proposal_path
    assert_match "1 件の提案を取り込みました", flash[:notice]
  end

  test "存在しない word_id が混ざるとフラッシュで知らせる" do
    sign_in_as(Admin.take)
    json = { version: "1", proposals: [ { word_id: 999_999, meaning: "無い語。" } ] }.to_json

    post admin_annotation_proposals_path, params: { proposals_json: json }
    assert_match "999999", flash[:notice]
  end

  test "壊れた JSON は 422 で貼り付け画面に戻す" do
    sign_in_as(Admin.take)
    assert_no_difference -> { AnnotationProposal.count } do
      post admin_annotation_proposals_path, params: { proposals_json: "{ 壊れた" }
    end
    assert_response :unprocessable_entity
    assert_select "p.flash--alert"
  end
end
