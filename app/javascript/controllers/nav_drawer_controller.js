import { Controller } from "@hotwired/stimulus"

// 狭幅ヘッダーのハンバーガーメニュー。ナビ+検索パネルの開閉を担当する。
export default class extends Controller {
  static targets = ["panel", "scrim", "button"]
  static values = { openLabel: String, closeLabel: String }

  connect() {
    this.escHandler = (event) => {
      if (event.key === "Escape") this.close()
    }
    document.addEventListener("keydown", this.escHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.escHandler)
  }

  toggle() {
    this.panelTarget.classList.contains("is-open") ? this.close() : this.open()
  }

  open() {
    this.panelTarget.classList.add("is-open")
    this.scrimTarget.classList.add("is-open")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.buttonTarget.setAttribute("aria-label", this.closeLabelValue)
    document.body.classList.add("nav-drawer-open")
  }

  close() {
    this.panelTarget.classList.remove("is-open")
    this.scrimTarget.classList.remove("is-open")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.setAttribute("aria-label", this.openLabelValue)
    document.body.classList.remove("nav-drawer-open")
  }
}
