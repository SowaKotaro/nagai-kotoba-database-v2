require "test_helper"

# 言語的特徴だけの再調査(Issue 76)の書き出し画面と、
# コンソールの「特徴なしで確定」の挙動。
class Admin::FeatureReviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(Admin.take)
  end

  def published_word_without_features(surface: "特徴未調査の語", reading: "トクチョウミチョウサノゴ")
    word = Word.create!(surface: surface, annotated_at: Time.current)
    sense = word.word_senses.create!(reading: reading, meaning: "テスト用")
    sense.word_origins << word_origins(:nihongo)
    [ word, sense ]
  end

  # --- 書き出し ---

  test "書き出し画面は未認証では開けない" do
    sign_out
    get export_features_admin_annotation_proposals_path
    assert_redirected_to new_session_path
  end

  test "書き出し画面に対象語義の JSON が出る" do
    _word, sense = published_word_without_features

    get export_features_admin_annotation_proposals_path
    assert_response :success
    assert_select "textarea#export_json"

    json = JSON.parse(css_select("textarea#export_json").first.text)
    assert_equal "linguistic_features_only", json["task"]
    assert_includes json["senses"].map { _1["sense_id"] }, sense.id
  end

  test "件数の上限を超える指定は丸められる" do
    get export_features_admin_annotation_proposals_path(limit: 9999)
    assert_response :success
    assert_select "input#export_limit[value=?]", Admin::AnnotationProposalsController::EXPORT_MAX_LIMIT.to_s
  end

  # --- 「特徴なしで確定」 ---

  test "特徴なしで確定すると調査済みになり、書き出しの対象から外れる" do
    word, sense = published_word_without_features
    assert_includes FeatureResearchExport.target_senses(limit: 100), sense

    patch review_features_admin_annotation_path(word)
    assert_redirected_to admin_annotation_path(word)

    assert_not_nil sense.reload.features_reviewed_at
    assert_not_includes FeatureResearchExport.target_senses(limit: 100), sense
  end

  test "特徴が付いている語義は確定の対象にしない" do
    word, sense = published_word_without_features
    sense.word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku),
                                      target: "特徴", target_reading: "トクチョウ")

    patch review_features_admin_annotation_path(word)

    assert_nil sense.reload.features_reviewed_at
  end

  test "特徴なしで確定は未認証ではできない" do
    word, sense = published_word_without_features
    sign_out

    patch review_features_admin_annotation_path(word)
    assert_redirected_to new_session_path
    assert_nil sense.reload.features_reviewed_at
  end

  test "コンソールに「特徴なしで確定」が出る(特徴が付いていれば出ない)" do
    word, sense = published_word_without_features

    get admin_annotation_path(word)
    assert_select "input[value=?]", I18n.t("admin.annotations.review_features")

    sense.word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku),
                                      target: "特徴", target_reading: "トクチョウ")

    get admin_annotation_path(word)
    assert_select "input[value=?]", I18n.t("admin.annotations.review_features"), count: 0
  end
end
