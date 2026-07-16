import { Controller } from "@hotwired/stimulus"

// 「保存して次へ」で語を公開する前のガード(Issue 68)。語義が最低限(読み・語種・ジャンル・
// 品詞・エンティティ)揃っていなければ確認を挟み、未完了のまま公開する事故を防ぐ。
// 完了済みは無確認で即公開して速度を殺さない。保留(hold)は公開しないのでスキップする
// (保留ボタンに data-publish-guard-skip が付く)。
export default class extends Controller {
  static values = { message: String }

  guard(event) {
    if (event.submitter && event.submitter.hasAttribute("data-publish-guard-skip")) return
    if (this.allComplete) return
    if (!window.confirm(this.messageValue)) event.preventDefault()
  }

  // 表示中(削除されていない)の語義がすべて完了(sense-completeness の is-complete)か。
  get allComplete() {
    const senses = [ ...this.element.querySelectorAll(".js-sense") ]
      .filter((sense) => sense.style.display !== "none")
    return senses.length > 0 && senses.every((sense) => sense.classList.contains("is-complete"))
  }
}
