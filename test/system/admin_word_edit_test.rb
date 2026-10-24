require "application_system_test_case"

# 単語の修正(Issue 108)の実機挙動。修正画面はコンソールと同じ注釈フォームの部品(Stimulus)を使うので、
# 部品がこの画面でもつながり、× で外した特徴が保存で消えることをブラウザで確かめる。
# 保存しても注釈状態が変わらないことなど、サーバの振る舞いは Admin::WordsControllerTest で見る。
class AdminWordEditTest < ApplicationSystemTestCase
  test "特徴で絞った一覧から修正画面を開き、特徴を × で外して保存すると、同じ一覧へ戻る" do
    word = words(:abc_murder)
    removed = word_sense_features(:murder_rendaku)
    system_sign_in
    visit admin_words_path(linguistic_feature_id: removed.linguistic_feature_id, feature_target: removed.target)
    click_expecting(expect_css: "h1.ann-word", text: word.surface) { find("td a", text: word.surface) }

    wait_for_stimulus "nested-form"
    assert_selector ".ann-feature", count: 2
    row = find(".ann-feature input[name$='[id]'][value='#{removed.id}']", visible: false)
          .find(:xpath, "ancestor::div[contains(@class, 'ann-feature')][1]", visible: false)
    # × はネイティブクリックの取りこぼし・遅れて届くのを避けて、JS の click() で 1 回だけ押す(ApplicationSystemTestCase の注記)
    execute_script("arguments[0].click()", row.find("button.ann-remove"))
    assert_selector ".ann-feature", count: 1

    click_expecting(expect_css: "#flash", text: "「#{word.surface}」を保存しました。") do
      find("input[type=submit][value='#{I18n.t("admin.words.edit.save")}']")
    end
    # 絞り込みを保った一覧へ戻り、外した特徴の語はもう出ない
    assert_selector "input[name=feature_target][value='#{removed.target}']"
    assert_selector "p.empty-note"
    assert_not WordSenseFeature.exists?(removed.id)
    assert_equal [ word_sense_features(:murder_jubako).id ], word_senses(:murder).word_sense_features.ids
    assert word.reload.annotation_done?
  end
end
