import { Controller } from "@hotwired/stimulus"

// キュー操作のキーボードショートカット(任意・補助)。
//   Enter=保存して次へ / →=スキップ / ←=戻る。
// テキスト入力中は無効化して、通常の入力を邪魔しない(タップ操作が主・キーは補助)。
export default class extends Controller {
  static targets = ["form", "skip", "back"]

  connect() {
    this.handler = this.onKey.bind(this)
    document.addEventListener("keydown", this.handler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handler)
  }

  onKey(event) {
    const tag = (event.target.tagName || "").toLowerCase()
    if (tag === "input" || tag === "textarea") return

    if (event.key === "Enter") {
      event.preventDefault()
      this.formTarget.requestSubmit()
    } else if (event.key === "ArrowRight" && this.hasSkipTarget) {
      event.preventDefault()
      this.skipTarget.click()
    } else if (event.key === "ArrowLeft" && this.hasBackTarget) {
      event.preventDefault()
      this.backTarget.click()
    }
  }
}
