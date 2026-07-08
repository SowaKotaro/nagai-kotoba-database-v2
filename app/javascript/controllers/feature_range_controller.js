import { Controller } from "@hotwired/stimulus"

// 言語学的特徴の「該当部分」を、単語と読みの文字を始点→終点でタップして指定する。
// 宿泊予約のチェックイン/アウト式:
//   1タップ目=始点(朱枠) / 2タップ目=終点(範囲を墨反転) / 3タップ目=始点を選び直す。
// 選んだ範囲の部分文字列を隠しフィールド(target / target_reading)へ書き込む。
// キーボードを使わずに指定できるのが目的(スマホ/タブレット対応)。
export default class extends Controller {
  static targets = ["surfaceStrip", "readingStrip", "targetField", "targetReadingField", "targetStartField", "result"]
  static values = { surface: String }

  connect() {
    this.sel = { t: { s: null, e: null }, r: { s: null, e: null } }
    this.readingInput = this.element.closest(".js-sense")?.querySelector(".js-reading")
    this.reading = this.readingInput ? this.readingInput.value : ""
    this.onReadingInput = () => {
      this.reading = this.readingInput.value
      this.sel.r = { s: null, e: null }
      this.renderStrip("r")
      this.commit()
    }
    if (this.readingInput) this.readingInput.addEventListener("input", this.onReadingInput)

    this.restoreFromFields()
    this.renderStrip("t")
    this.renderStrip("r")
    this.updateResult()
  }

  disconnect() {
    if (this.readingInput) this.readingInput.removeEventListener("input", this.onReadingInput)
  }

  chars(which) {
    return Array.from(which === "t" ? this.surfaceValue : this.reading)
  }

  // 永続化済みの target / target_reading から範囲を復元する。
  // 単語側は保存済みの出現位置(target_start)があればその箇所を、無ければ最初の一致箇所を採る
  // (同じ文字列が繰り返す語で、どの出現かを正しく復元するため)。
  restoreFromFields() {
    const start = this.hasTargetStartFieldTarget ? parseInt(this.targetStartFieldTarget.value, 10) : NaN
    this.restoreOne("t", this.targetFieldTarget.value, Number.isNaN(start) ? null : start)
    this.restoreOne("r", this.targetReadingFieldTarget.value, null)
  }

  restoreOne(which, value, atIndex) {
    if (!value) return
    const chars = this.chars(which)
    const sub = Array.from(value)
    const matches = (i) => i >= 0 && i + sub.length <= chars.length && sub.every((c, k) => chars[i + k] === c)
    if (atIndex != null && matches(atIndex)) {
      this.sel[which] = { s: atIndex, e: atIndex + sub.length - 1 }
      return
    }
    for (let i = 0; i + sub.length <= chars.length; i++) {
      if (matches(i)) {
        this.sel[which] = { s: i, e: i + sub.length - 1 }
        return
      }
    }
  }

  renderStrip(which) {
    const strip = which === "t" ? this.surfaceStripTarget : this.readingStripTarget
    const sel = this.sel[which]
    strip.innerHTML = ""
    this.chars(which).forEach((ch, i) => {
      const cell = document.createElement("button")
      cell.type = "button"
      cell.className = "ann-cell"
      cell.textContent = ch
      if (sel.s != null && sel.e != null && i >= Math.min(sel.s, sel.e) && i <= Math.max(sel.s, sel.e)) {
        cell.classList.add("is-sel")
      } else if (sel.s != null && sel.e == null && i === sel.s) {
        cell.classList.add("is-start")
      }
      cell.addEventListener("click", () => this.tap(which, i))
      strip.appendChild(cell)
    })
  }

  tap(which, i) {
    const sel = this.sel[which]
    if (sel.s == null || sel.e != null) { sel.s = i; sel.e = null }   // 新しく始点
    else if (i >= sel.s) { sel.e = i }                                // 終点確定
    else { sel.s = i }                                                // 始点を前へ
    this.renderStrip(which)
    this.commit()
  }

  commit() {
    this.targetFieldTarget.value = this.substring("t")
    this.targetReadingFieldTarget.value = this.substring("r")
    // 単語側の選択開始位置(出現箇所の識別子)を保存する。未選択なら空にする。
    if (this.hasTargetStartFieldTarget) {
      const sel = this.sel.t
      this.targetStartFieldTarget.value =
        sel.s != null && sel.e != null ? String(Math.min(sel.s, sel.e)) : ""
    }
    this.updateResult()
  }

  substring(which) {
    const sel = this.sel[which]
    if (sel.s == null || sel.e == null) return ""
    return this.chars(which).slice(Math.min(sel.s, sel.e), Math.max(sel.s, sel.e) + 1).join("")
  }

  updateResult() {
    const t = this.targetFieldTarget.value
    const r = this.targetReadingFieldTarget.value
    this.resultTarget.textContent = "→ " + (t || "（単語 未選択）") + " / " + (r || "（読み 未選択）")
  }
}
