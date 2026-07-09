import { Controller } from "@hotwired/stimulus"

// ヘッダーナビのプルダウン(「検索」→ ジャンル/索引/詳細検索)。
// 外側クリックと Escape で閉じ、aria-expanded を同期する。
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    // 開いた状態のまま Turbo にキャッシュされると、戻ったときにメニューが開いて見える
    this.beforeCacheHandler = () => this.close()
    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  // メニュー外をクリックしたときだけ閉じる(トリガー自身のクリックは toggle に任せる)
  closeOnOutside(event) {
    if (this.element.contains(event.target)) return
    this.close()
  }
}
