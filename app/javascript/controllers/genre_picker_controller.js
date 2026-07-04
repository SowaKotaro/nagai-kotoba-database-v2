import { Controller } from "@hotwired/stimulus"

// ジャンルの段階表示ピッカー(ドロップダウンを使わない)。
//   最初は大分類のみ。大を選ぶと中が出現、中を選ぶと小が出現(選ぶことで隠れた選択肢が登場)。
//   小(末端=level3)を選ぶと隠しフィールド genre_id にその id を書き込む。
//   各段に「その場追加」があり、選択中の親の下へ新しいジャンルを作って選択できる。
// 既にジャンルが設定済みの語では現在のパスだけ出し、「変更」で選び直しに切り替える。
export default class extends Controller {
  static targets = [
    "value", "current", "largeLevel", "largeChips",
    "mediumLevel", "mediumChips", "smallLevel", "smallChips"
  ]
  static values = { childrenUrl: String, createUrl: String }

  connect() {
    this.largeId = null
    this.mediumId = null
    // 大分類にも「その場追加」を用意する(複製時の二重付与を防ぐため既存を確認)。
    if (!this.largeChipsTarget.querySelector(".ann-add")) {
      this.largeChipsTarget.appendChild(this.addControl(this.largeChipsTarget, null, "pickLarge"))
    }
    // 未選択なら大分類から。設定済みなら現在パス表示のまま(largeLevel は隠す)。
    if (!this.valueTarget.value) this.reset()
  }

  // 「変更」: 現在パスを消して選び直しに入る。
  reset() {
    this.valueTarget.value = ""
    if (this.hasCurrentTarget) this.currentTarget.hidden = true
    this.largeLevelTarget.hidden = false
    this.mediumLevelTarget.hidden = true
    this.smallLevelTarget.hidden = true
    this.mediumChipsTarget.innerHTML = ""
    this.smallChipsTarget.innerHTML = ""
    this.deactivate(this.largeChipsTarget)
  }

  async pickLarge(event) {
    this.largeId = event.currentTarget.dataset.id
    this.activate(this.largeChipsTarget, event.currentTarget)
    this.valueTarget.value = ""
    this.smallLevelTarget.hidden = true
    this.smallChipsTarget.innerHTML = ""
    await this.fill(this.mediumChipsTarget, this.largeId, "pickMedium", this.largeId)
    this.mediumLevelTarget.hidden = false
  }

  async pickMedium(event) {
    this.mediumId = event.currentTarget.dataset.id
    this.activate(this.mediumChipsTarget, event.currentTarget)
    this.valueTarget.value = ""
    await this.fill(this.smallChipsTarget, this.mediumId, "pickSmall", this.mediumId)
    this.smallLevelTarget.hidden = false
  }

  pickSmall(event) {
    this.activate(this.smallChipsTarget, event.currentTarget)
    this.valueTarget.value = event.currentTarget.dataset.id
  }

  // 子ジャンルを取得してチップを敷き詰め、末尾に「その場追加」を付ける。
  async fill(container, parentId, action, createParentId) {
    container.innerHTML = ""
    try {
      const response = await fetch(`${this.childrenUrlValue}?parent_id=${encodeURIComponent(parentId)}`,
        { headers: { Accept: "application/json" } })
      if (response.ok) {
        const genres = await response.json()
        genres.forEach((g) => container.appendChild(this.chip(g.id, g.name, action)))
      }
    } catch { /* 取得失敗時は追加のみ可能 */ }
    container.appendChild(this.addControl(container, createParentId, action))
  }

  chip(id, name, action) {
    const b = document.createElement("button")
    b.type = "button"
    b.className = "ann-chip"
    b.dataset.id = id
    b.dataset.action = `genre-picker#${action}`
    b.textContent = name
    return b
  }

  addControl(container, parentId, action) {
    const wrap = document.createElement("span")
    wrap.className = "ann-add"
    const btn = document.createElement("button")
    btn.type = "button"; btn.className = "ann-add__btn"; btn.textContent = "＋ 追加"
    const input = document.createElement("input")
    input.type = "text"; input.className = "ann-add__input"; input.placeholder = "新しいジャンル"; input.hidden = true
    btn.addEventListener("click", () => { input.hidden = false; input.focus() })
    input.addEventListener("keydown", async (e) => {
      if (e.key === "Escape") { input.hidden = true; input.value = ""; return }
      if (e.key !== "Enter") return
      e.preventDefault()
      const name = input.value.trim()
      if (!name) return
      const created = await this.create(name, parentId)
      if (!created) return
      const c = this.chip(created.id, created.name, action)
      container.insertBefore(c, wrap)
      input.hidden = true; input.value = ""
      c.click() // 追加してすぐ選択(＝下の階層を開く / 末端なら genre_id セット)
    })
    wrap.appendChild(btn); wrap.appendChild(input)
    return wrap
  }

  async create(name, parentId) {
    try {
      const body = parentId ? { name, parent_id: parentId } : { name }
      const response = await fetch(this.createUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body: JSON.stringify(body)
      })
      if (!response.ok) return null
      return await response.json()
    } catch { return null }
  }

  activate(container, chip) {
    this.deactivate(container)
    chip.classList.add("is-on")
  }

  deactivate(container) {
    container.querySelectorAll(".ann-chip.is-on").forEach((c) => c.classList.remove("is-on"))
  }

  csrf() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
