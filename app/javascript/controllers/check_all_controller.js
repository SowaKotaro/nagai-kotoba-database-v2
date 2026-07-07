import { Controller } from "@hotwired/stimulus"

// 一覧の「全選択」。ヘッダのチェックで表示中の行チェックボックスを一括切替し、
// 行側の操作でヘッダの状態を追従させる(Issue 37 の一括アノテーション用)。
export default class extends Controller {
  static targets = ["toggle", "item"]

  toggle() {
    this.itemTargets.forEach((box) => { box.checked = this.toggleTarget.checked })
  }

  sync() {
    this.toggleTarget.checked =
      this.itemTargets.length > 0 && this.itemTargets.every((box) => box.checked)
  }
}
