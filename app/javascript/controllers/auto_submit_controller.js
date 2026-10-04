import { Controller } from "@hotwired/stimulus"

// コントローラを付けた要素(form)自身を送信する汎用コントローラ。data-controller は form に付け、
// 中の select などから change->auto-submit#submit で呼ぶ(単語一覧の並び順、管理の単語一覧の絞り込み)。
// form 以外に付けると動かない。JS 無効時は <noscript> の送信ボタンで代替する。
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
