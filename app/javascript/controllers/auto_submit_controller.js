import { Controller } from "@hotwired/stimulus"

// フォーム要素の変更で親フォームを送信する汎用コントローラ(一覧の並び順 select など)。
// JS 無効時は <noscript> の送信ボタンで代替する。
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
