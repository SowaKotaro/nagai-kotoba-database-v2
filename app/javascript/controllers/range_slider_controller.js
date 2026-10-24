import { Controller } from "@hotwired/stimulus"

// 読みの文字数の二つまみスライダー。範囲(下端・上端)と文言はサーバが渡す(SearchesHelper#reading_length_slider_data)。
//   一本のトラックに min/max 2つのツマミを重ね、隠しフィールド
//   reading_length_min / reading_length_max に値を書き込む。
//   上限が上端(maxValue)のときは「以上」の意味なので max は空にする(上限なし)。
//   下限が下端(minValue = 収録基準)のときも、それより短い語は収録しない=絞っていないので min を空にする
//   (送ると「◯文字以上」の条件として数えられ、区画どうしを OR で組んだとき全件に当たってしまう)。
//   トラックの上の度数分布の棒(bar。data-value に目盛りの値)は、選んだ範囲に入るものに is-selected を付け直す
//   (初期値はサーバが描く。JS が無いとスライダーごと動かないので、棒も初期値のまま)。
// メッセージは3種類(文言は ja.yml の searches.reading_length_slider):
//   1. max == 上端     → atLeast 「N文字以上」(両方 上端 でも「上端文字以上」)
//   2. min == max     → exact 「N文字」
//   3. それ以外        → between 「N文字以上M文字以下」
export default class extends Controller {
  static targets = ["minThumb", "maxThumb", "minField", "maxField", "message", "track", "bar"]
  static values = { min: Number, max: Number, atLeast: String, exact: String, between: String }

  connect() {
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

    // 隠しフィールド: 下限は下端より上のときだけ、上限は上端未満のときだけ送る(どちらも端=絞らない)。
    this.minFieldTarget.value = lo <= this.minValue ? "" : lo
    this.maxFieldTarget.value = hi >= this.maxValue ? "" : hi

    // トラックの塗り(選択範囲)の位置を --from / --to で渡す。色は CSS が持つ(選択範囲は --text)。
    if (this.hasTrackTarget) {
      const span = this.maxValue - this.minValue
      const a = ((lo - this.minValue) / span) * 100
      const b = ((hi - this.minValue) / span) * 100
      this.trackTarget.style.setProperty("--from", `${a}%`)
      this.trackTarget.style.setProperty("--to", `${b}%`)
    }

    this.barTargets.forEach((bar) => {
      const value = Number(bar.dataset.value)
      bar.classList.toggle("is-selected", value >= lo && value <= hi)
    })

    this.messageTarget.textContent = this.messageFor(lo, hi)
  }

  messageFor(lo, hi) {
    if (hi >= this.maxValue) return this.atLeastValue.replace("%{min}", lo)
    if (lo === hi) return this.exactValue.replace("%{min}", lo)
    return this.betweenValue.replace("%{min}", lo).replace("%{max}", hi)
  }
}
