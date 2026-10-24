import { Controller } from "@hotwired/stimulus"

// 一覧の「全選択」。ヘッダのチェックで表示中の行チェックボックスを一括切替し、
// 行側の操作でヘッダの状態を追従させる(管理の単語一覧の一括アノテーション(Issue 37)と、
// 収録リクエストの一覧で使う)。
// 一括切替はプログラムで checked を変えるので change が出ない。代わりに check-all:toggled を出す
// (単語の修正の一覧で、まとめて外す特徴の選択肢を選び直す bulk-detachment-features が受ける)。
export default class extends Controller {
  static targets = ["toggle", "item"]

  toggle() {
    this.itemTargets.forEach((box) => { box.checked = this.toggleTarget.checked })
    this.dispatch("toggled")
  }

  sync() {
    this.toggleTarget.checked =
      this.itemTargets.length > 0 && this.itemTargets.every((box) => box.checked)
  }
}
