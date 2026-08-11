import { Controller } from "@hotwired/stimulus"

// アノテーション・デッキ(まとめてアノテーション)のカード送り。
//   スマホ: 横スワイプ(CSS の scroll-snap がスクロールを担い、ここは位置の追従だけ)。
//   PC: 矢印ボタン・ドット・← / → キー。
// 併せて「n / m 完了」の集計を持つ。完了の判定そのものは各語義の sense-completeness が
// 付ける is-complete を数えるだけにして、判定の定義を二重に持たない。
export default class extends Controller {
  static targets = ["track", "card", "dot", "position", "complete", "prev", "next"]

  connect() {
    this.onScroll = () => this.scheduleSync()
    this.trackTarget.addEventListener("scroll", this.onScroll, { passive: true })
    this.onKey = (event) => this.key(event)
    document.addEventListener("keydown", this.onKey)
    this.sync()
    this.recount()
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this.onScroll)
    document.removeEventListener("keydown", this.onKey)
  }

  // ← / → でカードを送る。文字入力中はカーソル移動を邪魔しない(キーは補助・スワイプが主)。
  key(event) {
    const tag = (event.target.tagName || "").toLowerCase()
    if (tag === "input" || tag === "textarea" || tag === "select") return

    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.prev()
    }
  }

  next() { this.go(this.currentIndex + 1) }
  prev() { this.go(this.currentIndex - 1) }

  jump(event) { this.go(Number(event.currentTarget.dataset.index)) }

  // 指定のカードへ寄せる。前のカードで下までスクロールしていると次のカードの見出しが
  // 画面外から始まってしまうので、縦位置もデッキの先頭へ戻す。
  go(index) {
    const card = this.cardTargets[index]
    if (!card) return

    this.trackTarget.scrollTo({ left: card.offsetLeft, behavior: "smooth" })
    this.trackTarget.scrollIntoView({ block: "start", behavior: "smooth" })
  }

  // スクロール中は毎フレーム以上に走らせない。
  scheduleSync() {
    if (this.pending) return
    this.pending = true
    requestAnimationFrame(() => {
      this.pending = false
      this.sync()
    })
  }

  // 現在地(何枚目か)の表示・ドット・矢印の活殺を、実際のスクロール位置から更新する。
  sync() {
    const index = this.currentIndex
    this.positionTarget.textContent = index + 1
    this.dotTargets.forEach((dot, i) => dot.classList.toggle("is-on", i === index))
    this.prevTarget.disabled = index === 0
    this.nextTarget.disabled = index >= this.cardTargets.length - 1
  }

  // 現在地は「スクロール位置に最も近いカード」。カード幅で割る計算にすると、カード間の
  // 余白の分だけ後ろのカードでずれていくため、実際の位置(offsetLeft)と突き合わせる
  // (.deck-track は position: relative なので offsetLeft はトラック内の座標)。
  get currentIndex() {
    const left = this.trackTarget.scrollLeft
    let nearest = 0
    let shortest = Infinity

    this.cardTargets.forEach((card, index) => {
      const distance = Math.abs(card.offsetLeft - left)
      if (distance < shortest) {
        shortest = distance
        nearest = index
      }
    })
    return nearest
  }

  // 「n / m 完了」。カードは、表示中の語義がすべて is-complete なら完了とみなす
  // (publish-guard の判定と同じ数え方)。ドットにも印を移す。
  // 各語義の sense-completeness:changed(接続時にも飛ぶ)と、語義の削除など DOM が
  // 変わる操作(click)を合図に数え直す。
  recount() {
    let complete = 0
    this.cardTargets.forEach((card, i) => {
      const done = this.cardComplete(card)
      if (done) complete += 1
      this.dotTargets[i]?.classList.toggle("is-done", done)
    })
    this.completeTarget.textContent = complete
    this.element.classList.toggle("is-all-complete", complete === this.cardTargets.length)
  }

  cardComplete(card) {
    const senses = [ ...card.querySelectorAll(".js-sense") ].filter((sense) => sense.style.display !== "none")
    return senses.length > 0 && senses.every((sense) => sense.classList.contains("is-complete"))
  }
}
