require "application_system_test_case"

# 一括登録 step2(読み)のフロント検証。読みはカタカナのみ許し、中黒・空白などが混じった
# 行は送信を止める。ブラウザでしか確かめられない挙動なのでシステムテストで担保する。
# 読みの自動取得(ReadingExtractor)は CI に mecab が無くても安定させるためスタブする。
class AdminWordsReadingFormatTest < ApplicationSystemTestCase
  # この環境の chromedriver は日本語(CJK)の send_keys が入力欄に届かない(fill_in が空のまま)。
  # 値を JS で流し込み、input イベントを発火して Stimulus の検証を実際に走らせる。
  def type_japanese(selector, text)
    page.execute_script(<<~JS, find(selector), text)
      arguments[0].value = arguments[1];
      arguments[0].dispatchEvent(new Event("input", { bubbles: true }));
    JS
  end

  def click_next(label, expect_css:, **expect_options)
    click_expecting(expect_css: expect_css, **expect_options) do
      find("input[type=submit][value='#{label}']")
    end
  end

  test "読みにカタカナ以外が混じると step3 へ進めない" do
    system_sign_in

    # step1 → step2。サーバはテストと同じプロセスで動くため、ここでのスタブが効く。
    stub_method(ReadingExtractor, :call, ->(surfaces) { surfaces.map { "テンジョウテンゲユイガドクソン" } }) do
      visit new_admin_word_path
      type_japanese "textarea.bulk-input", "1. 天上天下唯我独尊"
      click_next I18n.t("admin.words.bulk.to_readings"), expect_css: "input.bulk-review__reading-input"
    end
    wait_for_stimulus "reading-format"
    assert_no_selector ".bulk-review__reading-error" # 初期表示ではエラーを出さない

    # 中黒を混ぜると入力時点でエラーが出る
    type_japanese "input.bulk-review__reading-input", "テンジョウテンゲ・ユイガドクソン"
    assert_selector ".bulk-review__reading-error", text: /カタカナ/
    assert_selector "input.bulk-review__reading-input.is-error"

    # 送信しても step2 に留まる(次のステップへ進まない)
    click_next I18n.t("admin.words.bulk.readings.to_duplicates"),
               expect_css: "input.bulk-review__reading-input[aria-invalid='true']"
    assert_selector "ol.steps li.is-current .steps__label", text: "読み"

    # 空白混じりも許さない
    type_japanese "input.bulk-review__reading-input", "テンジョウテンゲ ユイガドクソン"
    assert_selector "input.bulk-review__reading-input.is-error"

    # カタカナだけに直すとエラーが消え、step3(重複チェック)へ進める
    type_japanese "input.bulk-review__reading-input", "テンジョウテンゲユイガドクソン"
    assert_no_selector "input.bulk-review__reading-input.is-error"
    assert_no_selector ".bulk-review__reading-error"
    click_next I18n.t("admin.words.bulk.readings.to_duplicates"),
               expect_css: "ol.steps li.is-current .steps__label", text: "重複"
  end
end
