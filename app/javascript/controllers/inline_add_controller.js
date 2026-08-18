import { Controller } from "@hotwired/stimulus"

// マスタ(語種・品詞・エンティティ)のその場追加。
// 「＋追加」で入力欄を開き、Enter で JSON POST。返ってきた {id, name} から
// チップ(隠しチェックボックス/ラジオ + ラベル)を生成し、選択状態にして差し込む。
// 生成するチップの雛形は <template data-inline-add-target="chip"> に置き、
// __ID__ / __NAME__ を置換する(name 属性はサーバ側で正しく描画済み)。
//
// 失敗しても画面が変わらないと「押しても何も起きない」ようにしか見えないので、
// 失敗の理由は必ず入力欄の隣に出す。既に同名がある場合はサーバが既存を返すので、
// 新しいチップを足さずに既存のチップを選ぶ。
export default class extends Controller {
  static targets = ["field", "input", "chip"]
  static values = { url: String, labels: Object }

  open() {
    this.fieldTarget.hidden = false
    this.hideMessage()
    this.inputTarget.focus()
  }

  key(event) {
    // 日本語入力(IME)の変換を確定する Enter は送信に使わない。ここで拾うと変換途中の
    // 文字列を登録してしまう。確定後にもう一度押された Enter だけを送信に使う。
    if (event.isComposing || event.keyCode === 229) return

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
    if (this.busy) return // 連打による二重登録(と、その結果の重複エラー)を防ぐ

    this.busy = true
    this.hideMessage()
    try {
      const result = await post(this.urlValue, { name }, this.labelsValue)
      if (result.error) {
        this.showMessage(result.error, true)
        this.inputTarget.focus()
        return
      }

      this.select(result.record)
      // 選択済みのチップを DOM に挿すだけでは change が飛ばないので明示的に知らせる。
      this.dispatch("added", { detail: { id: result.record.id } })
      this.close()
      if (result.existing) this.showMessage(this.labelsValue.selected_existing, false)
    } finally {
      this.busy = false
    }
  }

  // 既にチップがあればそれを選ぶ(サーバが既存を返した場合)。無ければ雛形から作る。
  select(record) {
    const chips = this.element.parentElement
    const input = chips.querySelector(`.ann-chip__input[value="${record.id}"]`)
    if (input) {
      input.checked = true
      return
    }

    const html = this.chipTarget.innerHTML
      .replaceAll("__ID__", () => String(record.id))
      .replaceAll("__NAME__", () => escapeHtml(record.name))
    this.element.insertAdjacentHTML("beforebegin", html)
  }

  close() {
    this.fieldTarget.hidden = true
    this.inputTarget.value = ""
  }

  // メッセージ欄は入力欄の外(コントローラ直下)に置く。入力欄を閉じても
  // 「既にあるものを選びました」を読めるようにするため。
  // 語義の複製で DOM ごとコピーされることがあるので、既にあれば使い回す。
  messageElement() {
    let el = this.element.querySelector(":scope > .ann-add__msg")
    if (!el) {
      el = document.createElement("span")
      el.className = "ann-add__msg"
      this.element.appendChild(el)
    }
    return el
  }

  showMessage(text, isError) {
    const el = this.messageElement()
    el.textContent = text
    el.classList.toggle("is-error", isError)
    el.hidden = false
  }

  hideMessage() {
    const el = this.element.querySelector(":scope > .ann-add__msg")
    if (el) el.hidden = true
  }
}

// マスタ追加の POST。成否と理由を必ず返す({record, existing} または {error})。
export async function post(url, body, labels) {
  let response
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify(body)
    })
  } catch {
    return { error: labels.network_error }
  }

  // セッション切れだとログイン画面の HTML が返る(200 だが JSON ではない)。
  const data = await response.json().catch(() => null)
  if (!data) return { error: labels.unexpected_response }
  if (response.ok) return { record: data, existing: Boolean(data.existing) }

  const errors = Array.isArray(data.errors) ? data.errors.join(" / ") : ""
  return { error: errors || labels.failed.replace("%{status}", response.status) }
}

export function escapeHtml(text) {
  const el = document.createElement("span")
  el.textContent = text
  return el.innerHTML
}

function csrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  return meta ? meta.content : ""
}
