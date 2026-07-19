import { Controller } from "@hotwired/stimulus"

// 墨枠セグメントボタンでパネル(事前描画済みのチャート等)を切り替える。
// 統計ページの「文字数/モーラ数」「全期間/6か月/3か月」で使う(docs/stats.md §3・§4)。
// パネルはすべてサーバ側で描画しておき、ここでは hidden の付け替えだけを行う。
export default class extends Controller {
  static targets = ["button", "panel"]

  show(event) {
    const key = event.currentTarget.dataset.panelKey
    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.panelKey === key))
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.panelKey !== key
    })
  }
}
