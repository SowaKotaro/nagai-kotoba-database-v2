import { Controller } from "@hotwired/stimulus"

// ネストしたフォームの行(語義・言語学的特徴)を動的に追加/削除する。
// テンプレート内のプレースホルダを一意な値へ置換して新規行を挿入する。
// 同一コントローラを入れ子で使うため、プレースホルダは行ごとに変えられるようにしている。
export default class extends Controller {
  static targets = ["container", "template"]
  static values = { placeholder: { type: String, default: "NEW_RECORD" } }

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replaceAll(this.placeholderValue, Date.now().toString())
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const item = event.target.closest("[data-nested-form-item]")
    if (!item) return

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
