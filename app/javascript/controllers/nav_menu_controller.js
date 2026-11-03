import { Controller } from "@hotwired/stimulus"

// 押すと開くパネル。ヘッダーナビの「検索」のプルダウンと、ホームの探し方の入口の開くボタン(home/_search_way_menu)が使う。
// 外側クリックと Escape で閉じ、aria-expanded を同期する。同じ画面に複数あっても、別のトリガーを押すと
// それが外側クリックになって、開いていたほうは閉じる(開くのは常に 1 つ)。JS が無いとパネルは開かない(hidden のまま)。
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
