require "test_helper"

# 言語学的特徴だけの再調査(Issue 76)の書き出し画面と、コンソールの「特徴なしで確定」の挙動。
# 書き出し対象の抽出条件は FeatureResearchExportTest で見る。
class Admin::FeatureReviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(admins(:one))
  end

  def published_word_without_features(surface: "特徴未調査の語", reading: "トクチョウミチョウサノゴ")
    word = create_published_word(surface: surface, reading: reading, meaning: "テスト用")
    sense = word.word_senses.first
    sense.word_origins << word_origins(:nihongo)
    [ word, sense ]
  end

  # --- 書き出し ---

  test "書き出し画面に対象語義の JSON が出る" do
    _word, sense = published_word_without_features

    get export_features_admin_annotation_proposals_path
    assert_response :success

    json = JSON.parse(css_select("textarea#export_json").first.text)
    assert_equal "linguistic_features_only", json["task"]
    assert_includes json["senses"].map { _1["sense_id"] }, sense.id
  end

  test "「語種に日本語を含む語だけ」は既定で効き、チェックを外して送ると全語種を書き出す" do
    _word, japanese_sense = published_word_without_features
    english = create_published_word(surface: "英語だけの未調査の語", reading: "エイゴダケノミチョウサノゴ", meaning: "テスト用")
    english_sense = english.word_senses.first
    english_sense.word_origins << word_origins(:eigo)
    exported_ids = -> { JSON.parse(css_select("textarea#export_json").first.text)["senses"].map { _1["sense_id"] } }

    get export_features_admin_annotation_proposals_path
    assert_includes exported_ids.call, japanese_sense.id
    assert_not_includes exported_ids.call, english_sense.id
    # チェックボックスは外すと何も送らないので、直前の hidden が "0" を送る(form.check_box と同じ形)
    assert_select "input[type=hidden][name=japanese_only][value='0'] + input[type=checkbox][name=japanese_only][value='1']"

    # チェックを外して送った(hidden の 0 だけが届く)
    get export_features_admin_annotation_proposals_path(japanese_only: "0")
    assert_includes exported_ids.call, english_sense.id
    assert_select "input[type=checkbox][name=japanese_only]:not([checked])"

    # チェックを入れて送った(hidden の 0 と checkbox の 1 の両方が届き、後ろの 1 が勝つ)
    get "#{export_features_admin_annotation_proposals_path}?japanese_only=0&japanese_only=1"
    assert_not_includes exported_ids.call, english_sense.id
  end

  test "件数の上限を超える指定は丸められる" do
    get export_features_admin_annotation_proposals_path(limit: 9999)
    assert_response :success
    assert_select "input#export_limit[value=?]", Admin::AnnotationProposalsController::EXPORT_MAX_LIMIT.to_s
    # 入力欄の上限もサーバの上限と同じ値(ずれると、ブラウザが上限までの値を拒む)
    assert_select "input#export_limit[max=?]", Admin::AnnotationProposalsController::EXPORT_MAX_LIMIT.to_s
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
