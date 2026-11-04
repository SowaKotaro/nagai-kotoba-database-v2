import { Controller } from "@hotwired/stimulus"

// 900px 以下のヘッダーのドロワー(docs/design.md §5.1)。ハンバーガーで、ナビ(「検索」の折り畳みとテーマの
// 切り替えを含む)を収めた右からのパネルを開閉する。広い幅ではパネルがヘッダーの右側にそのまま並ぶので、ここは働かない。
// 開くと頭の閉じるボタンへ、閉じるとハンバーガーへフォーカスを移す(閉じたパネルは CSS が visibility でも隠すので、Tab で入らない)。
// 閉じるのは、閉じるボタン・スクリムのクリック・Escape・Turbo のキャッシュの直前(開いたまま残すと、戻ったときに開いて見える)。
// Escape とキャッシュは shared/_header の data-action で受ける。JS が無いとハンバーガーが効かず、狭幅ではナビに届かない(docs/design.md §6)。
export default class extends Controller {
  static targets = ["panel", "scrim", "button", "close"]
  static values = { openLabel: String, closeLabel: String }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.panelTarget.classList.add("is-open")
    this.scrimTarget.classList.add("is-open")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.buttonTarget.setAttribute("aria-label", this.closeLabelValue)
    document.body.classList.add("nav-drawer-open")
    this.closeTarget.focus()
  }

  // Escape は開いていなくても届く(ホームの選択肢のシートなど、ほかの部品を閉じる Escape)ので、閉じているときは何もしない
  close() {
    if (!this.isOpen) return

    const focusWasInside = this.panelTarget.contains(document.activeElement)
    this.panelTarget.classList.remove("is-open")
    this.scrimTarget.classList.remove("is-open")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.setAttribute("aria-label", this.openLabelValue)
    document.body.classList.remove("nav-drawer-open")
    if (focusWasInside) this.buttonTarget.focus()
  }

  get isOpen() {
    return this.panelTarget.classList.contains("is-open")
  }
}
