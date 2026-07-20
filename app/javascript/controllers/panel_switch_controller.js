import { Controller } from "@hotwired/stimulus"

// 墨枠セグメントボタンでパネル(事前描画済みのチャート等)を切り替える。
// 統計ページの「文字数/モーラ数」「全期間/6か月/3か月」で使う(docs/stats.md §3・§4)。
// パネルはすべてサーバ側で描画しておき、ここでは hidden の付け替えだけを行う。
//
// hideOnConnect を立てると、サーバは hidden を付けずに全パネルを描画しておき、
// 接続時にこちらで初期表示へ畳む(ランキングページ)。JS が無い環境では全パネルが
// そのまま縦に並ぶので、内容が読めなくならない。
export default class extends Controller {
  static targets = ["button", "panel"]
  static values = { hideOnConnect: Boolean }

  connect() {
    if (this.hideOnConnectValue) this.showKey(this.activeKey())
  }

  show(event) {
    this.showKey(event.currentTarget.dataset.panelKey)
  }

  showKey(key) {
    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.panelKey === key))
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.panelKey !== key
    })
  }

  // サーバが aria-pressed="true" を付けたボタン(無ければ先頭)のパネルを初期表示にする。
  activeKey() {
    const pressed = this.buttonTargets.find((button) => button.getAttribute("aria-pressed") === "true")
    return (pressed || this.buttonTargets[0])?.dataset.panelKey
  }
}
