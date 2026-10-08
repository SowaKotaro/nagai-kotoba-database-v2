import { Controller } from "@hotwired/stimulus"

// URL などのテキストをクリップボードにコピーする。コピー後は一時的に完了表示に切り替える。
// data-clipboard-text-value にコピー対象、data-clipboard-copied-label-value に完了時の文言。
export default class extends Controller {
  static values = { text: String, copiedLabel: String }
  static targets = ["label"]

  connect() {
    // 完了の表示のまま Turbo にキャッシュされると、「戻る」で戻ったページは「コピーしました」のまま戻らない
    this.beforeCacheHandler = () => this.restoreLabel()
    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)
  }

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

    // 戻す先の文言は最初の 1 回だけ覚える(完了の表示中に押し直したとき、完了の文言を「元」として覚えないように)
    this.originalLabel ??= this.labelTarget.textContent
    this.labelTarget.textContent = this.copiedLabelValue
    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => this.restoreLabel(), 2000)
  }

  restoreLabel() {
    clearTimeout(this.resetTimer)
    if (this.originalLabel === undefined) return

    this.labelTarget.textContent = this.originalLabel
  }

  disconnect() {
    clearTimeout(this.resetTimer)
    document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
  }
}
