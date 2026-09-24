import { Controller } from "@hotwired/stimulus"

// テキスト欄で Ctrl+Enter(Mac は ⌘+Enter)を押すと、そのフォームを送る(貼り付けてすぐ取り込む)。
// 素の Enter は改行のまま。フォーム要素に付け、keydown を受ける。
export default class extends Controller {
  submit(event) {
    if (event.key !== "Enter" || !(event.ctrlKey || event.metaKey) || event.isComposing) return

    event.preventDefault()
    this.element.requestSubmit()
  }
}
