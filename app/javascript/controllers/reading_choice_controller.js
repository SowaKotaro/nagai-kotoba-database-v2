import { Controller } from "@hotwired/stimulus"

// 一括登録 step2 の読み選択。候補チップをクリックすると、その読みを読み欄に流し込む。
// JS が無くても読み欄は手入力でき、チップは候補の一覧として見えるだけ(段階的強化)。
export default class extends Controller {
  static targets = ["input", "chip"]

  choose(event) {
    const reading = event.currentTarget.dataset.reading
    this.inputTarget.value = reading
    this.chipTargets.forEach((chip) => {
      chip.classList.toggle("is-active", chip.dataset.reading === reading)
    })
  }
}
