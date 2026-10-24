import { Controller } from "@hotwired/stimulus"

// 一覧の「全選択」。ヘッダのチェックで表示中の行チェックボックスを一括切替し、
// 行側の操作でヘッダの状態を追従させる(管理の単語一覧の一括アノテーション(Issue 37)と、
// 収録リクエストの一覧で使う)。
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
