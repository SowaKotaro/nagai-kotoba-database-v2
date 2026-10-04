import { Controller } from "@hotwired/stimulus"
import { allSensesComplete } from "controllers/support/senses"

// 「保存して次へ」で語を公開する前のガード(Issue 68)。語義が最低限(読み・語種・ジャンル・
// 品詞・エンティティ)揃っていなければ確認を挟み、未完了のまま公開する事故を防ぐ。
// 完了済みは無確認で即公開して速度を殺さない。保留(hold)は公開しないのでスキップする
// (保留ボタンに data-publish-guard-skip が付く)。
export default class extends Controller {
  static values = { message: String }

  guard(event) {
    if (event.submitter && event.submitter.hasAttribute("data-publish-guard-skip")) return
    // 表示中(削除されていない)の語義がすべて完了なら確認しない(数え方は support/senses。deck と同じ)
    if (allSensesComplete(this.element)) return
    if (!window.confirm(this.messageValue)) event.preventDefault()
  }
}
