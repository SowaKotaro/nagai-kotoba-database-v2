import { Controller } from "@hotwired/stimulus"

// 文字種(char_type_pattern)の入力補助。手入力は無く、キー入力はこのコントローラだけが行う。
// 「あ」「ア」「漢」「A」「@」のキーで末尾へ1文字追記し、⌫(backspace)キーで末尾の1文字を
// 削除する。値は送信用の hidden(field) に持ち、ターミナル風の表示欄(display)へ反映する。
// これで常に妥当なパターンだけが入る(バリデーション兼用)。
export default class extends Controller {
  static targets = ["field", "display"]

  append(event) {
    this.value = this.value + event.params.char
  }

  remove() {
    // 記号はいずれも1コードポイントだが、絵文字等の不測の入力に備えて
    // コードポイント単位で末尾を1つ落とす。
    this.value = Array.from(this.value).slice(0, -1).join("")
  }

  get value() {
    return this.fieldTarget.value
  }

  set value(next) {
    this.fieldTarget.value = next
    if (this.hasDisplayTarget) this.displayTarget.textContent = next
  }
}
