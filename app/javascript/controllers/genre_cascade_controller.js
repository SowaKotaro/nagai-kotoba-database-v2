import { Controller } from "@hotwired/stimulus"

// ジャンルの大→中→小 依存ドロップダウン。
// 大を選ぶと中、中を選ぶと小の選択肢を取得して差し替える。
// 実際に送信されるのは小分類(genre_id)のみ。大・中の select は name を持たせない。
export default class extends Controller {
  static targets = ["large", "medium", "small"]
  static values = { url: String }

  largeChanged() {
    this.clear(this.smallTarget)
    this.populate(this.mediumTarget, this.largeTarget.value)
  }

  mediumChanged() {
    this.populate(this.smallTarget, this.mediumTarget.value)
  }

  async populate(select, parentId) {
    this.clear(select)
    if (!parentId) return

    const response = await fetch(`${this.urlValue}?parent_id=${encodeURIComponent(parentId)}`, {
      headers: { Accept: "application/json" }
    })
    if (!response.ok) return

    const genres = await response.json()
    for (const genre of genres) {
      const option = document.createElement("option")
      option.value = genre.id
      option.textContent = genre.name
      select.appendChild(option)
    }
  }

  clear(select) {
    select.innerHTML = ""
    const blank = document.createElement("option")
    blank.value = ""
    select.appendChild(blank)
  }
}
