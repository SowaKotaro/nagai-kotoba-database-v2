require "application_system_test_case"

# コピーのボタン(clipboard_controller.js)。完了の表示(「コピーしました」)は 2 秒で元の文言に戻る。
# 単語詳細の「URL をコピー」で確かめる(管理画面の書き出しのコピー欄も同じコントローラ)。
class ClipboardCopyTest < ApplicationSystemTestCase
  BUTTON = "button.share__btn[data-action='clipboard#copy']".freeze
  LABEL = "#{BUTTON} [data-clipboard-target=label]".freeze

  test "2 秒以内に続けて押しても、完了の表示は元の文言に戻る" do
    visit word_path(words(:abc_murder))
    wait_for_stimulus("clipboard")
    # ヘッドレスの Chrome ではクリップボードへ書けないことがあるので、書き込みは成功したことにする
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", { value: { writeText: () => Promise.resolve() }, configurable: true })
    JS
    original = find(LABEL).text

    find(BUTTON).click
    assert_selector LABEL, text: I18n.t("words.show.share.copied")
    find(BUTTON).click
    assert_selector LABEL, text: original, wait: 5
  end
end
