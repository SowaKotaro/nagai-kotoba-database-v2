import { Controller } from "@hotwired/stimulus"

// 下へ送ると流れ去るヘッダーを、上へ少し戻したときに上端から降ろす(docs/design.md §5.1)。
// 目的: 統計や一覧のように長いページでは、ほかのページへ移る入口(ナビとドロワー)がヘッダーにしか無く、読み進めるとそれが消える。
//   常に貼り付ける案と、右下の「トップへ戻る」ボタンは退けた(§12)。ふだんは今までどおり流れ去り、上へ戻すときだけ降りてくる。
// 使う画面: 公開側の全ページ(shared/_header。管理画面には付けない)。
// JS が無いとき: 従来どおり流れ去るだけ(CSS は data-header-reveal が付くまで何もしない)。
// 連携: nav-drawer:open / :close(ドロワーを開いている間は出したままにする)、focusin(キーボードで入ったら出す)、
//   turbo:before-cache(出入りの状態を畳んでからキャッシュさせる)、turbo:load(ページの切り替えやキャッシュからの復元で
//   スクロール位置が飛んだのを、「上へ戻した」と数えないよう、基準の位置を取り直す)。いずれも shared/_header の data-action で受ける。
// 出入りは CSS が top の遷移で描く: 隠れているときの top は「ヘッダーの高さぶん上」(流れ去ったあと、ちょうど画面の外で留まる)で、
//   .is-revealed が付くと 0 になる。transform を使わないのは、変形した祖先の中では position: fixed のドロワーが画面ではなく
//   ヘッダーを基準に置かれてしまうため。
// ページの頭(y <= 0)では何もせず、流れる位置のまま(その位置では貼り付いても見た目は同じ)。
const SHOW_DISTANCE = 24 // この距離(px)だけ続けて上へ戻すと降ろす。「ちょっと戻す」で降りるが、指のぶれでは降りない
const HIDE_DISTANCE = 16 // この距離(px)だけ続けて下へ送ると畳む

export default class extends Controller {
  connect() {
    this.held = false
    this.rising = 0
    this.falling = 0
    this.lastY = this.scrollTop
    this.frame = null

    this.element.classList.remove("is-revealed")
    this.measure()
    this.element.dataset.headerReveal = ""

    this.onScroll = () => {
      if (!this.frame) this.frame = requestAnimationFrame(() => this.update())
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.resizeObserver = new ResizeObserver(() => this.measure())
    this.resizeObserver.observe(this.element)
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    this.resizeObserver.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  // ドロワーを開いている間は出したままにする(ハンバーガーの × がドロワーの頭と同じ高さに並ぶ)
  hold() {
    this.held = true
    this.setRevealed(true)
  }

  release() {
    this.held = false
    this.sync()
  }

  // 基準の位置と数えかけの距離を、いまの位置から取り直す(飛んだ位置を、動いた距離に数えない)
  sync() {
    this.rising = 0
    this.falling = 0
    this.lastY = this.scrollTop
  }

  // キーボードでヘッダーに入ったら出す。マウスで押したときは、押せる位置にあるので動かさない
  reveal(event) {
    if (event.target.matches(":focus-visible")) this.setRevealed(true)
  }

  reset() {
    this.setRevealed(false)
  }

  update() {
    this.frame = null
    const y = this.scrollTop
    const delta = y - this.lastY
    this.lastY = y
    if (this.held || delta === 0) return

    if (y <= 0) {
      this.rising = this.falling = 0
      this.setRevealed(false)
    } else if (delta < 0) {
      this.falling = 0
      this.rising -= delta
      if (this.rising >= SHOW_DISTANCE) this.setRevealed(true)
    } else {
      this.rising = 0
      this.falling += delta
      // キーボードの焦点がヘッダーの中にある間は畳まない(見えない所に焦点が残らないように)
      if (this.falling >= HIDE_DISTANCE && !this.element.querySelector(":focus-visible")) this.setRevealed(false)
    }
  }

  setRevealed(revealed) {
    this.element.classList.toggle("is-revealed", revealed)
  }

  // 隠れているときの top に使う、ヘッダー自身の高さ(狭幅で変わるので、大きさが変わるたびに測り直す)
  measure() {
    const height = Math.ceil(this.element.getBoundingClientRect().height)
    this.element.style.setProperty("--header-height", `${height}px`)
  }

  // iOS のゴム伸び(端を越えて引いて戻る)を「上へ戻した」と数えないよう、ページの端に丸める
  get scrollTop() {
    const max = document.documentElement.scrollHeight - window.innerHeight
    return Math.max(0, Math.min(window.scrollY, max))
  }
}
