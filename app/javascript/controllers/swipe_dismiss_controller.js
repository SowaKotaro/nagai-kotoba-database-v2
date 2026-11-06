import { Controller } from "@hotwired/stimulus"

// 画面の下から出てきたシートを、下へのスワイプで閉じる(2026-11-06 オーナー指示。docs/design.md §5.2)。
// 目的: 狭幅(767px 以下)でホームの探し方の選択肢は、画面の下からせり上がるシートになる。下から出てきたものは、
//   指を下へ払えば元に戻れるようにする(ドロワーは左右のスワイプでは閉じない)。
// 使う画面: ホームの探し方のシート(home/_search_way_menu の .search-ways__panel)。
// 動き: シートの頭から中身までどこをなぞっても、指に付いて下がる。96px 以上下げるか、速く払ったら閉じ、足りなければ元の位置へ戻る。
//   中身が上へスクロールされているときは、ふつうのスクロールを優先する(いちばん上にいて、下へなぞったときだけ引き下げる)。
// JS が無いとき・タッチでないとき: 何もしない(閉じるボタンと外側のタップは、nav-menu が受け持つ)。広い幅(吊り下げ)でも何もしない。
// 連携: 閉じると決めたら swipe-dismiss:dismiss を出す(data-action で nav-menu#close につなぐ)。
// touchmove は passive にできない(引き下げ中にページと中身のスクロールを止めるため preventDefault する)ので、
// data-action ではなく addEventListener で受ける。
const DISMISS_DISTANCE = 96 // px。これだけ下げて離したら閉じる
const DISMISS_VELOCITY = 0.5 // px/ms。これより速く払ったら、距離が短くても閉じる(下の SWIPE_MIN_DISTANCE 以上)
const SWIPE_MIN_DISTANCE = 24 // px。払って閉じるときの最低の距離(指がかすっただけで閉じないように)
const START_SLOP = 8 // px。これを超えて動くまでは、タップか、スクロールか、引き下げかを決めない

export default class extends Controller {
  connect() {
    this.tracking = false
    this.dragging = false
    this.handlers = {
      touchstart: (event) => this.start(event),
      touchmove: (event) => this.move(event),
      touchend: (event) => this.end(event),
      touchcancel: (event) => this.end(event)
    }
    this.element.addEventListener("touchstart", this.handlers.touchstart, { passive: true })
    this.element.addEventListener("touchmove", this.handlers.touchmove, { passive: false })
    this.element.addEventListener("touchend", this.handlers.touchend)
    this.element.addEventListener("touchcancel", this.handlers.touchcancel)
  }

  disconnect() {
    for (const [type, handler] of Object.entries(this.handlers)) this.element.removeEventListener(type, handler)
  }

  start(event) {
    this.dragging = false
    this.tracking = event.touches.length === 1 && this.sheet && this.element.scrollTop <= 0
    if (!this.tracking) return

    this.startY = this.lastY = event.touches[0].clientY
    this.lastTime = event.timeStamp
    this.velocity = 0
  }

  move(event) {
    if (!this.tracking) return

    const y = event.touches[0].clientY
    const distance = y - this.startY
    if (!this.dragging) {
      if (distance <= -START_SLOP || this.element.scrollTop > 0) {
        this.tracking = false // 上へなぞった・中身がスクロールされた: ふつうのスクロール
        return
      }
      if (distance < START_SLOP) return

      this.dragging = true
      this.element.style.transition = "none"
    }

    event.preventDefault()
    const elapsed = event.timeStamp - this.lastTime
    if (elapsed > 0) this.velocity = (y - this.lastY) / elapsed
    this.lastY = y
    this.lastTime = event.timeStamp
    this.offset = Math.max(0, distance - START_SLOP)
    this.element.style.translate = `0 ${this.offset}px`
  }

  end(event) {
    this.tracking = false
    if (!this.dragging) return

    this.dragging = false
    const dismiss = event.type === "touchend" &&
      (this.offset >= DISMISS_DISTANCE || (this.velocity >= DISMISS_VELOCITY && this.offset >= SWIPE_MIN_DISTANCE))
    // 指に付けるために切っていた transition と位置を戻す。閉じるときは、いまの位置から閉じる側の動きで下へ抜け、
    // 戻すときは、いまの位置から開く側の動きで元の位置へ戻る(どちらも CSS の遷移が続きを描く)
    this.element.style.transition = ""
    this.element.style.translate = ""
    if (dismiss) this.dispatch("dismiss")
  }

  // シートとして画面の下に固定されているか(広い幅の吊り下げのパネルは absolute)
  get sheet() {
    return getComputedStyle(this.element).position === "fixed"
  }
}
