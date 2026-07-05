import { Controller } from "@hotwired/stimulus"

// 読みの文字数の二つまみスライダー(10〜30)。
//   一本のトラックに min/max 2つのツマミを重ね、隠しフィールド
//   reading_length_min / reading_length_max に値を書き込む。
//   上限が MAX(30) のときは「以上」の意味なので max は空にする(上限なし)。
// メッセージは3種類:
//   1. max == MAX     → 「N文字以上」(両方 MAX でも「30文字以上」)
//   2. min == max     → 「N文字」
//   3. それ以外        → 「N文字以上M文字以下」
export default class extends Controller {
  static targets = ["minThumb", "maxThumb", "minField", "maxField", "message", "track"]
  static values = { min: Number, max: Number }

  connect() {
    this.MIN = this.minValue || 10
    this.MAX = this.maxValue || 30
    this.update()
  }

  // min が max を追い越さないよう補正してから反映する。
  input(event) {
    let lo = Number(this.minThumbTarget.value)
    let hi = Number(this.maxThumbTarget.value)
    if (lo > hi) {
      if (event && event.target === this.minThumbTarget) hi = lo
      else lo = hi
      this.minThumbTarget.value = lo
      this.maxThumbTarget.value = hi
    }
    this.update()
  }

  update() {
    const lo = Number(this.minThumbTarget.value)
    const hi = Number(this.maxThumbTarget.value)

    // 隠しフィールド: 下限は常に、上限は MAX 未満のときだけ送る(MAX=上限なし)。
    this.minFieldTarget.value = lo
    this.maxFieldTarget.value = hi >= this.MAX ? "" : hi

    // トラックの塗り(選択範囲)を朱で示す。
    if (this.hasTrackTarget) {
      const span = this.MAX - this.MIN
      const a = ((lo - this.MIN) / span) * 100
      const b = ((hi - this.MIN) / span) * 100
      this.trackTarget.style.setProperty("--from", `${a}%`)
      this.trackTarget.style.setProperty("--to", `${b}%`)
    }

    this.messageTarget.textContent = this.messageFor(lo, hi)
  }

  messageFor(lo, hi) {
    if (hi >= this.MAX) return `${lo}文字以上`
    if (lo === hi) return `${lo}文字`
    return `${lo}文字以上${hi}文字以下`
  }
}
