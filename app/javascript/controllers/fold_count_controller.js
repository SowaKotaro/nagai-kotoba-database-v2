import { Controller } from "@hotwired/stimulus"

// 詳細検索(/search)のフォーム全体に付け、折り畳み(details)の見出しへ配下の選択数を出し入れする。
//   折り畳みは条件の区画(searches/_section)と、その中のジャンルの階層(searches/_genre_filter)の 2 段。
//   開閉は details 要素のブラウザ標準挙動に任せ、このコントローラは「畳んだ状態でも選択が分かる」ように
//   チェックボックスを選び直したとき(change)にバッジを付け直すだけ。
//   JS が無いときは、サーバが描いた初期値のバッジのまま(選び直しても数は変わらない)。
//   バッジを持たない区画(テキスト欄・スライダーなど)は数えない。
//   上位と下位のジャンルを同時に選んだ場合の優先はサーバ側(WordSenseSearch)が扱う。
export default class extends Controller {
  static targets = ["fold", "count"]

  sync() {
    this.foldTargets.forEach((fold) => {
      // その折り畳みの見出しのバッジ(入れ子の下位の折り畳みのバッジではなく、いちばん近い details のもの)
      const badge = this.countTargets.find((target) => target.closest("details") === fold)
      if (!badge) return
      const count = fold.querySelectorAll("input[type=checkbox]:checked").length
      badge.hidden = count === 0
      badge.textContent = count === 0 ? "" : count
    })
  }
}
