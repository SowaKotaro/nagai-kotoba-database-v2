import { Controller } from "@hotwired/stimulus"

// ネストしたフォームの行(語義・言語学的特徴)を動的に追加/削除する。
// テンプレート内のプレースホルダを一意な値へ置換して新規行を挿入する。
// 同一コントローラを入れ子で使うため、プレースホルダは行ごとに変えられるようにしている。
export default class extends Controller {
  static targets = ["container", "template", "addButton"]
  // max は行数の上限(0 = 無制限)。上限を持たない既存フォームは指定しないので挙動は変わらない。
  static values = {
    placeholder: { type: String, default: "NEW_RECORD" },
    max: { type: Number, default: 0 }
  }

  connect() {
    this.refreshAddButton()
  }

  add(event) {
    event.preventDefault()
    if (this.atMax) return

    const html = this.templateTarget.innerHTML.replaceAll(this.placeholderValue, Date.now().toString())
    this.containerTarget.insertAdjacentHTML("beforeend", html)
    this.refreshAddButton()
  }

  remove(event) {
    event.preventDefault()
    const item = event.target.closest("[data-nested-form-item]")
    if (!item) return
    this.removeItem(item)
    this.refreshAddButton()
  }

  // 上限に達したら追加ボタンを押せなくする(ボタンを置いていないフォームでは何もしない)。
  refreshAddButton() {
    if (!this.hasAddButtonTarget) return
    this.addButtonTarget.disabled = this.atMax
  }

  get atMax() {
    return this.maxValue > 0 && this.rowCount >= this.maxValue
  }

  // 直下の行だけを数える(入れ子で使われるため子孫まで拾わない)。
  // 削除済み(_destroy を立てて隠した)行は枠を消費しないので除く。
  get rowCount() {
    return [...this.containerTarget.querySelectorAll(":scope > [data-nested-form-item]")]
      .filter((item) => item.style.display !== "none").length
  }

  removeItem(item) {
    // 永続化済みの行は _destroy を立てて非表示にする(送信時に削除される)。
    // 新規行も同様に _destroy を立てれば、Rails 側は新規レコードとして無視する。
    const destroyField = item.querySelector("input[data-nested-form-destroy]")
    if (destroyField) {
      destroyField.value = "1"
      item.style.display = "none"
    } else {
      item.remove()
    }
  }
}
