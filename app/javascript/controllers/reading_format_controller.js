import { Controller } from "@hotwired/stimulus"

// 一括登録 step2 の読みのフロント検証。読みはカタカナ(長音符を含む)だけを許し、
// ひらがな・漢字・中黒・空白などが混じった行はエラーにして次のステップへ進ませない。
// 「調査結果を反映」(formaction 付き)の送信は、読みを直す前の中間操作なので検証しない。
// 空欄は「自動取得できなかった行」を表すため、ここではエラーにしない(登録時に弾かれる)。
const KATAKANA_ONLY = /^[ァ-ヶー]+$/

export default class extends Controller {
  static targets = ["input"]

  // 入力のたびに、その行だけを検証する。
  validateField(event) {
    this.mark(event.target)
  }

  // 送信時に全行を検証し、1行でも不正なら送信を止めて最初の不正行へ移動する。
  validateAll(event) {
    if (event.submitter?.hasAttribute("formaction")) return

    const invalid = this.inputTargets.filter((input) => !this.mark(input))
    if (invalid.length === 0) return

    event.preventDefault()
    invalid[0].focus()
  }

  // 検証結果を入力欄に反映し、妥当なら true を返す。
  mark(input) {
    const valid = input.value === "" || KATAKANA_ONLY.test(input.value)
    input.classList.toggle("is-error", !valid)
    input.setAttribute("aria-invalid", String(!valid))

    const error = input.closest("td")?.querySelector(".bulk-review__reading-error")
    if (error) error.hidden = valid

    return valid
  }
}
