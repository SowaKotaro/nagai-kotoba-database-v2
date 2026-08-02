import { Controller } from "@hotwired/stimulus"

// 収録リクエストの読み欄で字数を数え、収録基準(読み◯文字以上)を満たすかをその場で示す。
// 基準に満たなくても送信は妨げない(選別は運営が行う)ので、表示は情報提供に徹する。
export default class extends Controller {
  static targets = ["input", "output"]
  static values = { min: Number, unit: String, satisfied: String, short: String }

  connect() {
    this.update()
  }

  update() {
    // サロゲートペア(絵文字など)を1文字として数えるため、コードポイントで分解する。
    const length = [...this.inputTarget.value.trim()].length
    const satisfied = length >= this.minValue

    this.outputTarget.textContent =
      length === 0 ? "" : `${length}${this.unitValue} — ${satisfied ? this.satisfiedValue : this.shortValue}`
    this.outputTarget.classList.toggle("reading-counter--ok", length > 0 && satisfied)
  }
}
