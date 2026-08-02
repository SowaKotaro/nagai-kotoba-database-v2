require "application_system_test_case"

# 収録リクエスト・フォーム(Issue 75)の実機挙動。
# 行の追加(上限つき)・読みの字数カウンタ・重複チェックの turbo-frame 差し替えは
# ブラウザでしか確認できないため、ここで担保する。
class WordRequestFormTest < ApplicationSystemTestCase
  MISSING_WORD = "検索しても見つからない長い言葉".freeze

  test "検索して見つからなかった語をその場でリクエストできる" do
    visit words_path(q: MISSING_WORD)
    assert_text I18n.t("words.index.empty_filtered")

    click_on I18n.t("words.index.request_link")

    # 探していたキーワードが引き継がれている
    assert_selector "#word_request_items_attributes_0_surface[value='#{MISSING_WORD}']"

    fill_in "word_request_items_attributes_0_reading", with: "ケンサクシテモミツカラナイナガイコトバ"
    submit_after_thinking

    assert_equal MISSING_WORD, WordRequestItem.last.surface
  end

  test "行を増やせるが上限で止まる" do
    visit new_request_path
    wait_for_stimulus "nested-form"

    add_button = I18n.t("word_requests.new.add_row")
    (WordRequest::MAX_ITEMS - 1).times do |i|
      click_expecting(expect_css: ".request-row", count: i + 2) { find("button", text: add_button) }
    end

    # 上限に達したら追加ボタンは押せなくなる
    assert_selector "button[disabled]", text: add_button
  end

  test "読みの字数が収録基準に届くと表示が変わる" do
    visit new_request_path
    wait_for_stimulus "reading-counter"

    fill_in "word_request_items_attributes_0_reading", with: "ミジカイ"
    assert_selector ".reading-counter", text: I18n.t("word_requests.reading_counter.short",
                                                    min: WordSense::MIN_READING_LENGTH)
    assert_no_selector ".reading-counter--ok"

    fill_in "word_request_items_attributes_0_reading", with: "ジュウブンニナガイヨミカタ"
    assert_selector ".reading-counter--ok",
                    text: I18n.t("word_requests.reading_counter.satisfied", min: WordSense::MIN_READING_LENGTH)
  end

  test "重複チェックで未収録だと分かる" do
    visit new_request_path

    fill_in "word_request_items_attributes_0_surface", with: MISSING_WORD
    click_expecting(expect_css: ".dup-note--none") { find("button", text: I18n.t("word_requests.new.check")) }
    assert_text I18n.t("word_requests.duplicates.none_title")

    # チェックしただけでは何も保存されない
    assert_equal 0, WordRequest.count
  end

  test "重複チェックで収録済みだと分かるが、送信は妨げられない" do
    visit new_request_path

    fill_in "word_request_items_attributes_0_surface", with: words(:abc_murder).surface
    click_expecting(expect_css: ".dup-note--exact") { find("button", text: I18n.t("word_requests.new.check")) }
    assert_link words(:abc_murder).surface

    submit_after_thinking
  end

  private

  # 送信して受付を確認する。フォーム表示から一定時間内の送信は自動投稿とみなして
  # 捨てる仕様(WordRequestFormToken)のため、人が入力した分の時間経過を作ってから押す。
  # 実時間を待つと遅くなるので、サーバ側の時計だけ進める(時間トラップ自体の検証は結合テスト)。
  def submit_after_thinking
    assert_difference "WordRequestItem.count", 1 do
      travel(WordRequestFormToken::MIN_ELAPSED + 1.second) do
        click_on I18n.t("word_requests.new.submit")
        assert_text I18n.t("word_requests.create.created")
      end
    end
  end
end
