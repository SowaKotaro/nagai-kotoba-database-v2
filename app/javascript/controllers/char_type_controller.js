import { Controller } from "@hotwired/stimulus"

// 文字タイプ列(char_type_pattern)の入力補助。
// 「あ」「ア」「漢」「A」「@」のキーを押すたびに、対応する記号を入力欄の末尾へ追記する。
// 削除や並べ替えは入力欄の通常のテキスト編集で行う。
export default class extends Controller {
  static targets = ["field"]

  append(event) {
    this.fieldTarget.value += event.params.char
  }
}
