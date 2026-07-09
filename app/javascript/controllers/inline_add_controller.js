import { Controller } from "@hotwired/stimulus"

// マスタ(語種・品詞・エンティティ)のその場追加。
// 「＋追加」で入力欄を開き、Enter で JSON POST。返ってきた {id, name} から
// チップ(隠しチェックボックス/ラジオ + ラベル)を生成し、選択状態にして差し込む。
// 生成するチップの雛形は <template data-inline-add-target="chip"> に置き、
// __ID__ / __NAME__ を置換する(name 属性はサーバ側で正しく描画済み)。
export default class extends Controller {
  static targets = ["field", "input", "chip"]
  static values = { url: String }

  open() {
    this.fieldTarget.hidden = false
    this.inputTarget.focus()
  }

  key(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.submit()
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  async submit() {
    const name = this.inputTarget.value.trim()
    if (!name) return

    let data
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ name })
      })
      if (!response.ok) return
      data = await response.json()
    } catch { return }

    const html = this.chipTarget.innerHTML.replaceAll("__ID__", data.id).replaceAll("__NAME__", data.name)
    this.element.insertAdjacentHTML("beforebegin", html)
    // 選択済みのチップを DOM に挿すだけでは change が飛ばないので明示的に知らせる。
    this.dispatch("added", { detail: { id: data.id } })
    this.close()
  }

  close() {
    this.fieldTarget.hidden = true
    this.inputTarget.value = ""
  }
}

function csrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  return meta ? meta.content : ""
}
