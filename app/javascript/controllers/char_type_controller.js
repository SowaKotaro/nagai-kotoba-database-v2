import { Controller } from "@hotwired/stimulus"

// 文字種(char_type_pattern)の入力補助。手入力は無く、キー入力はこのコントローラだけが行う。
// 「あ」「ア」「漢」「A」「@」のキーで末尾へ1文字追記し、⌫(backspace)キーで末尾の1文字を
// 削除する。値は送信用の hidden(field) に持ち、ターミナル風の表示欄(display)へ反映する。
// これで常に妥当なパターンだけが入る(バリデーション兼用)。
export default class extends Controller {
  static targets = ["field", "display", "lowerKey"]
  // 文字種の記号は Ruby(CharTypePattern)が正なので、ビューから受け取る。
  static values = { lower: String, upper: String }

  append(event) {
    this.value = this.value + event.params.char
  }

  remove() {
    // 記号はいずれも1コードポイントだが、絵文字等の不測の入力に備えて
    // コードポイント単位で末尾を1つ落とす。
    this.value = Array.from(this.value).slice(0, -1).join("")
  }

  // 大文字小文字トグル(Aa)の状態変化を受け取る。区別しないときは「a」が「A」として
  // 扱われるため、「a」キーを隠し、組み立て済みのパターンの「a」も「A」に畳む
  // (表示と検索の意味を一致させる。畳んだ「a」はトグルを戻しても復元しない)。
  caseSensitivityChanged(event) {
    const strict = event.detail.strict
    if (this.hasLowerKeyTarget) this.lowerKeyTarget.hidden = !strict
    if (!strict) this.value = this.value.replaceAll(this.lowerValue, this.upperValue)
  }

  get value() {
    return this.fieldTarget.value
  }

  set value(next) {
    this.fieldTarget.value = next
    if (this.hasDisplayTarget) this.displayTarget.textContent = next
  }
}
