import { Controller } from "@hotwired/stimulus"

// URL などのテキストをクリップボードにコピーする。コピー後は一時的に完了表示に切り替える。
// data-clipboard-text-value にコピー対象、data-clipboard-copied-label-value に完了時の文言。
export default class extends Controller {
  static values = { text: String, copiedLabel: String }
  static targets = ["label"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.flashCopied()
    } catch {
      // クリップボードが使えない環境では選択操作にフォールバックせず、何もしない。
    }
  }

  flashCopied() {
    if (!this.hasLabelTarget) return

    const original = this.labelTarget.textContent
    this.labelTarget.textContent = this.copiedLabelValue
    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => {
      this.labelTarget.textContent = original
    }, 2000)
  }

  disconnect() {
    clearTimeout(this.resetTimer)
  }
}
