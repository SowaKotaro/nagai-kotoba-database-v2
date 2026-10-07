import { Controller } from "@hotwired/stimulus"

// 検索の絞り込み用ジャンル階層(折り畳み)。
//   開閉は details 要素のブラウザ標準挙動に任せ、このコントローラは
//   「畳んだ状態でも選択が分かる」ように、各折り畳み(details)の summary へ
//   配下の選択数を出し入れするだけ。JS 無効でも初期値はサーバ側で描画済み。
//   上位と下位を同時に選んだ場合の優先はサーバ側(WordSenseSearch)が扱う。
export default class extends Controller {
  static targets = ["fold", "count"]

  sync() {
    this.foldTargets.forEach((fold) => {
      const count = fold.querySelectorAll("input:checked").length
      // その折り畳みの見出しのバッジ(入れ子の下位の折り畳みのバッジではなく、いちばん近い details のもの)
      const badge = this.countTargets.find((target) => target.closest("details") === fold)
      if (!badge) return
      badge.hidden = count === 0
      badge.textContent = count === 0 ? "" : count
    })
  }
}
