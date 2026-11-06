import { Controller } from "@hotwired/stimulus"

// 押すと開くパネル。ヘッダーナビの「検索」のプルダウンと、ホームの探し方の入口の開くボタン(home/_search_way_menu)が使う。
// 外側クリックと Escape で閉じ、aria-expanded を同期する。同じ画面に複数あっても、別のトリガーを押すと
// それが外側クリックになって、開いていたほうは閉じる(開くのは常に 1 つ)。JS が無いとパネルは開かない(hidden のまま)。
// 例外: 狭幅のドロワーの中の「検索」は、吊り下げずにその場で開閉する折り畳み(パネルが position: static)なので、外側クリックでは畳まない。
// ドロワーの中のほかの行(テーマの切り替えなど)を押すたびに畳まれて、行の高さが変わってしまうため(2026-11-06 オーナー指摘)。
// 畳むのはトリガーの再押下・Escape・Turbo のキャッシュの直前。
// 開いた直後の間だけ、パネルに is-entering を付ける(layout.css が、ヘッダーの「検索」の中の行を上から順に出す。ほかのパネルには規則が無い)。
export default class extends Controller {
  static targets = ["trigger", "panel"]

  // 行が出終わるまでの目安(ms)。CSS の遅れ(80ms + 45ms × 行数。5 行で約 300ms)と出る時間(380ms)に足りる長さ
  static enteringDuration = 1200

  connect() {
    // 開いた状態のまま Turbo にキャッシュされると、戻ったときにメニューが開いて見える
    this.beforeCacheHandler = () => this.close()
    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
    clearTimeout(this.enteringTimer)
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.classList.add("is-entering")
    clearTimeout(this.enteringTimer)
    this.enteringTimer = setTimeout(() => this.panelTarget.classList.remove("is-entering"), this.constructor.enteringDuration)
  }

  close() {
    clearTimeout(this.enteringTimer)
    this.panelTarget.classList.remove("is-entering")
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  // メニュー外をクリックしたときだけ閉じる(トリガー自身のクリックは toggle に任せる)
  closeOnOutside(event) {
    if (this.element.contains(event.target)) return
    if (this.inline) return
    this.close()
  }

  // ドロワーの中で、その場に開閉する折り畳みになっているか(layout.css の 900px 以下)。吊り下げ・シートは absolute / fixed
  get inline() {
    return getComputedStyle(this.panelTarget).position === "static"
  }
}
