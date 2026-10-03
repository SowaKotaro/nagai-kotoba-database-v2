import { Controller } from "@hotwired/stimulus"

// 統計ページ §7「母音と子音」の母音のつながり。ノードを押して母音の並びをたどり、
// その並びを持つ語の検索へ進む導線を出す。
//
// 押すのは線ではなくノードにする。線は最も太くても 3.2px(StatsHelper::GRAPH_MAX_EDGE。選んだ線の
// CSS の stroke-width も同じ値)しかなく、350 本が交差するので狙って押せない(交点では別の線を掴んでしまう)。
//
// 選び方の決まり(鎖を伸ばす・控え・繋ぎ込み・全部外す・引き直す・控えだけ外す)の正は
// docs/stats.md の統計ページ §7 の章にある。ここには写さないので、規則を変えるときは文書を先に直す。
//
// JS が無い環境では図がそのまま出るだけで、失われるのはこの導線だけ。
export default class extends Controller {
  static targets = ["node", "edge", "readout", "pick", "link"]
  // path: 検索のパス(クエリはここで組む)。label: 「{from}〜{to}拍目: {rows}」の雛形
  static values = { path: String, label: String }

  connect() {
    this.chain = []
    this.pending = null
    this.render()
  }

  choose(event) {
    event.preventDefault()
    const node = event.currentTarget

    // 選び直し: 鎖の中の節をもう一度押したら全部外す。控えなら控えだけ外す
    if (this.chain.includes(node)) {
      this.chain = []
      this.pending = null
      return this.render()
    }
    if (node === this.pending) {
      this.pending = null
      return this.render()
    }

    const position = this.positionOf(node)
    const head = this.chain[0]
    const tail = this.chain[this.chain.length - 1]

    if (this.chain.length === 0) {
      this.chain = [node]
    } else if (this.covers(position)) {
      // 同じ拍の別の段 → そこから引き直す
      this.chain = [node]
      this.pending = null
    } else if (position === this.positionOf(head) - 1) {
      this.chain.unshift(node)
    } else if (position === this.positionOf(tail) + 1) {
      this.chain.push(node)
    } else if (this.pending && Math.abs(position - this.positionOf(this.pending)) === 1) {
      // 控えの隣が決まった。ここで初めて古い鎖を捨てる
      this.chain = position > this.positionOf(this.pending) ? [this.pending, node] : [node, this.pending]
      this.pending = null
    } else {
      // 離れた拍。鎖はそのまま残す(あいだが後から埋まるかもしれない)
      this.pending = node
    }

    this.absorbPending()

    this.render()
  }

  // 控えの節が鎖の隣まで来たら、あいだが埋まったということなので繋ぎ込む
  // (1:ア - 2:イ と控えの 4:オ があるところへ 3:ウ を押したら、1〜4 の一続きにする)。
  // 鎖が控えの拍を越えた/同じ拍を取ったときは、控えは役目を終える。
  absorbPending() {
    if (!this.pending || this.chain.length === 0) return

    const position = this.positionOf(this.pending)
    if (this.covers(position)) {
      this.pending = null
    } else if (position === this.positionOf(this.chain[0]) - 1) {
      this.chain.unshift(this.pending)
      this.pending = null
    } else if (position === this.positionOf(this.chain[this.chain.length - 1]) + 1) {
      this.chain.push(this.pending)
      this.pending = null
    }
  }

  render() {
    this.edgeTargets.forEach((edge) => edge.classList.remove("is-selected"))
    this.nodeTargets.forEach((node) => node.classList.remove("is-picked"))
    this.chain.forEach((node) => node.classList.add("is-picked"))
    if (this.pending) this.pending.classList.add("is-picked")

    for (let index = 0; index < this.chain.length - 1; index++) {
      const edge = this.edgeBetween(this.chain[index], this.chain[index + 1])
      if (edge) edge.classList.add("is-selected")
    }

    if (this.chain.length < 2) {
      this.readoutTarget.hidden = true
      return
    }

    const from = this.positionOf(this.chain[0])
    const to = this.positionOf(this.chain[this.chain.length - 1])
    const vowels = this.chain.map((node) => node.dataset.vowel).join("")
    this.pickTarget.textContent = this.labelValue
      .replace("{from}", from)
      .replace("{to}", to)
      .replace("{rows}", this.chain.map((node) => node.dataset.row).join(" → "))
    // 形式の正はサーバの WordSenseSearch::VOWEL_TRANSITION_FORMAT(並びは 2〜15 拍、拍位置は
    // VOWEL_TRANSITION_MAX_POSITION まで)。JS は上限を知らず、範囲外の条件はサーバが黙って捨てる
    this.linkTarget.href = `${this.pathValue}?vowel_transition=${from}-${vowels}`
    this.readoutTarget.hidden = false
  }

  // 前後に並ぶ2つの節を結ぶ線(0 件の組は線が無いので undefined)。
  edgeBetween(left, right) {
    return this.edgeTargets.find((edge) => (
      edge.dataset.position === left.dataset.position &&
      edge.dataset.from === left.dataset.vowel &&
      edge.dataset.to === right.dataset.vowel
    ))
  }

  // その拍位置が今の鎖に含まれているか。
  covers(position) {
    if (this.chain.length === 0) return false

    return position >= this.positionOf(this.chain[0]) &&
           position <= this.positionOf(this.chain[this.chain.length - 1])
  }

  positionOf(node) {
    return Number(node.dataset.position)
  }
}
