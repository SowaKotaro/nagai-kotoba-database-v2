require "application_system_test_case"

# コピーのボタン(clipboard_controller.js)。完了の表示(「コピーしました」)は 2 秒で元の文言に戻る。
# 単語詳細の「URL をコピー」で確かめる(管理画面の書き出しのコピー欄も同じコントローラ)。
class ClipboardCopyTest < ApplicationSystemTestCase
  BUTTON = "button.share__btn[data-action='clipboard#copy']".freeze
  LABEL = "#{BUTTON} [data-clipboard-target=label]".freeze

  test "2 秒以内に続けて押しても、完了の表示は元の文言に戻る" do
    original = visit_word_with_clipboard_stubbed

    find(BUTTON).click
    assert_selector LABEL, text: I18n.t("words.show.share.copied")
    find(BUTTON).click
    assert_selector LABEL, text: original, wait: 5
  end

  test "完了の表示中に別のページへ移って「戻る」と、元の文言で戻る" do
    original = visit_word_with_clipboard_stubbed
    find(BUTTON).click
    assert_selector LABEL, text: I18n.t("words.show.share.copied")

    # Turbo はページを移る前の見た目をキャッシュし、「戻る」ではそれを出す
    page.execute_script("Turbo.visit(#{words_path.to_json})")
    assert_no_selector BUTTON
    page.go_back
    assert_selector LABEL, text: original
  end

  private

  # 単語詳細を開き、元の文言を返す。
  def visit_word_with_clipboard_stubbed
    visit word_path(words(:abc_murder))
    wait_for_stimulus("clipboard")
    # ヘッドレスの Chrome ではクリップボードへ書けないことがあるので、書き込みは成功したことにする
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", { value: { writeText: () => Promise.resolve() }, configurable: true })
    JS
    find(LABEL).text
  end
end
