import { Controller } from "@hotwired/stimulus"

// 一覧の「全選択」。ヘッダのチェックで表示中の行チェックボックスを一括切替し、
// 行側の操作でヘッダの状態を追従させる(Issue 37 の一括アノテーション用)。
// 行を Shift+クリックすると、直前にクリックした行からその行までを同じ状態にそろえる。
// 無効(disabled)の行は選べない行なので、どちらでも切り替えない。
export default class extends Controller {
  static targets = ["toggle", "item"]

  connect() {
    this.onClick = this.selectRange.bind(this)
    this.element.addEventListener("click", this.onClick)
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick)
  }

  toggle() {
    this.enabledItems().forEach((box) => { box.checked = this.toggleTarget.checked })
  }

  sync() {
    const items = this.enabledItems()
    this.toggleTarget.checked = items.length > 0 && items.every((box) => box.checked)
  }

  // クリックの時点で、押した行のチェックはもう切り替わっている。
  selectRange(event) {
    const box = event.target
    if (!this.itemTargets.includes(box)) return

    if (event.shiftKey && this.lastItem && this.lastItem !== box) {
      const items = this.itemTargets
      const from = items.indexOf(this.lastItem)
      const to = items.indexOf(box)
      items.slice(Math.min(from, to), Math.max(from, to) + 1)
        .filter((item) => !item.disabled)
        .forEach((item) => { item.checked = box.checked })
      this.sync()
    }
    this.lastItem = box
  }

  enabledItems() {
    return this.itemTargets.filter((box) => !box.disabled)
  }
}
