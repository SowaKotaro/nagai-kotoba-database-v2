import { Controller } from "@hotwired/stimulus"
import { post } from "controllers/inline_add_controller"

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
  static values = { childrenUrl: String, createUrl: String, preselect: Array, labels: Object }

  connect() {
    this.largeId = null
    this.mediumId = null
    // 大分類にも「その場追加」を用意する。イベントは JS で結び付けているため、
    // 語義の複製(outerHTML のコピー)や Turbo のキャッシュ復元で DOM だけが写された
    // 分にはハンドラが付いていない(押しても入力欄が開かない/Enter が効かない)。
    // 使い回さず毎回作り直して、複製された語義でも必ず動くようにする。
    this.largeChipsTarget.querySelectorAll(":scope > .ann-add").forEach((el) => el.remove())
    this.largeChipsTarget.appendChild(this.addControl(this.largeChipsTarget, null, "pickLarge"))
    // 小分類が確定済み(genre_id あり)なら現在パス表示のまま。未確定でも、提案の反映で
    // 大・中まで一致していれば(preselect)そこまで自動で開く。何も無ければ大分類から。
    if (this.valueTarget.value) return
    if (this.preselectValue.length) this.openTo(this.preselectValue)
    else this.reset()
  }

  // 提案反映時に、既存の木で一致した祖先(大 / 大・中)までピッカーを開いておく。
  // ids: [大id] なら中分類の選択肢まで、[大id, 中id] なら小分類の選択肢まで出す。
  async openTo(ids) {
    const [largeId, mediumId] = ids.map(String)
    const largeChip = this.largeChipsTarget.querySelector(`.ann-chip[data-id="${largeId}"]`)
    if (!largeChip) return this.reset()

    this.largeId = largeId
    this.activate(this.largeChipsTarget, largeChip)
    await this.fill(this.mediumChipsTarget, largeId, "pickMedium", largeId)
    this.mediumLevelTarget.hidden = false

    if (mediumId) {
      const mediumChip = this.mediumChipsTarget.querySelector(`.ann-chip[data-id="${mediumId}"]`)
      if (mediumChip) {
        this.mediumId = mediumId
        this.activate(this.mediumChipsTarget, mediumChip)
        await this.fill(this.smallChipsTarget, mediumId, "pickSmall", mediumId)
        this.smallLevelTarget.hidden = false
      }
    }
    this.notifyChanged()
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
    this.notifyChanged()
  }

  async pickLarge(event) {
    this.largeId = event.currentTarget.dataset.id
    this.activate(this.largeChipsTarget, event.currentTarget)
    this.valueTarget.value = ""
    this.smallLevelTarget.hidden = true
    this.smallChipsTarget.innerHTML = ""
    await this.fill(this.mediumChipsTarget, this.largeId, "pickMedium", this.largeId)
    this.mediumLevelTarget.hidden = false
    this.notifyChanged()
  }

  async pickMedium(event) {
    this.mediumId = event.currentTarget.dataset.id
    this.activate(this.mediumChipsTarget, event.currentTarget)
    this.valueTarget.value = ""
    await this.fill(this.smallChipsTarget, this.mediumId, "pickSmall", this.mediumId)
    this.smallLevelTarget.hidden = false
    this.notifyChanged()
  }

  pickSmall(event) {
    this.activate(this.smallChipsTarget, event.currentTarget)
    this.valueTarget.value = event.currentTarget.dataset.id
    this.notifyChanged()
  }

  // 隠しフィールドを直接書き換えるので input/change は飛ばない。
  // 選択状態に依存する表示(語義カードの完了枠)へ明示的に知らせる。
  notifyChanged() {
    this.dispatch("changed")
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
    btn.type = "button"; btn.className = "ann-add__btn"; btn.textContent = this.labelsValue.add
    const input = document.createElement("input")
    input.type = "text"; input.className = "ann-add__input"
    input.placeholder = this.labelsValue.genre_placeholder; input.hidden = true
    const msg = document.createElement("span")
    msg.className = "ann-add__msg"; msg.hidden = true

    const context = { container, parentId, action, wrap, input, msg }
    btn.addEventListener("click", () => { input.hidden = false; msg.hidden = true; input.focus() })
    input.addEventListener("keydown", (event) => this.addKey(event, context))
    wrap.append(btn, input, msg)
    return wrap
  }

  async addKey(event, context) {
    const { input, msg } = context
    // 日本語入力(IME)の変換を確定する Enter は送信に使わない。ここで拾うと変換途中の
    // 文字列を登録してしまう。確定後にもう一度押された Enter だけを送信に使う。
    if (event.isComposing || event.keyCode === 229) return

    if (event.key === "Escape") {
      input.hidden = true
      input.value = ""
      msg.hidden = true
      return
    }
    if (event.key !== "Enter") return

    event.preventDefault()
    const name = input.value.trim()
    if (!name) return
    if (input.dataset.busy) return // 連打による二重登録(と、その結果の重複エラー)を防ぐ

    input.dataset.busy = "1"
    msg.hidden = true
    try {
      const result = await this.create(name, context.parentId)
      if (result.error) {
        // 失敗を黙って握りつぶすと「Enter を押しても何も起きない」ようにしか見えない。
        msg.textContent = result.error
        msg.classList.add("is-error")
        msg.hidden = false
        input.focus()
        return
      }

      input.hidden = true
      input.value = ""
      if (result.existing) {
        msg.textContent = this.labelsValue.selected_existing
        msg.classList.remove("is-error")
        msg.hidden = false
      }
      await this.selectAdded(result.record, context)
    } finally {
      delete input.dataset.busy
    }
  }

  // 追加したジャンルをその場で選ぶ(＝下の階層を開く / 末端なら genre_id セット)。
  // Stimulus の data-action は MutationObserver 経由で後から結び付くため、挿入直後の
  // chip.click() では拾われないことがある。ここでは同じ処理を直接呼ぶ。
  selectAdded(record, context) {
    const { container, action, wrap } = context
    let chip = container.querySelector(`.ann-chip[data-id="${record.id}"]`)
    if (!chip) {
      chip = this.chip(record.id, record.name, action)
      container.insertBefore(chip, wrap)
    }
    return this[action]({ currentTarget: chip })
  }

  async create(name, parentId) {
    const body = parentId ? { name, parent_id: parentId } : { name }
    return await post(this.createUrlValue, body, this.labelsValue)
  }

  activate(container, chip) {
    this.deactivate(container)
    chip.classList.add("is-on")
  }

  deactivate(container) {
    container.querySelectorAll(".ann-chip.is-on").forEach((c) => c.classList.remove("is-on"))
  }
}
