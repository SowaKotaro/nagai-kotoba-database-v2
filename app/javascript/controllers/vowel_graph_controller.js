import { Controller } from "@hotwired/stimulus"

// 統計 §7「母音のつながり」。ノードを押して母音の並びをたどり、
// その並びを持つ語の検索へ進む導線を出す。
//
// 押すのは線ではなくノードにする。線は最も太くても 3.2px しかなく、
// 350 本が交差するので狙って押せない(交点では別の線を掴んでしまう)。
//
// 選び方の決まり(オーナー指示 2026-09-10):
//   - 鎖の端の隣を押せば、前へも後ろへも伸びる(1:ア - 2:オ - 3:イ …)
//   - 離れた拍を押しても鎖は消さない。あいだの拍は後から埋まるかもしれないので、
//     その節は「控え」として選んだ状態にしておくだけにする
//   - 控えの隣を押して2つ目が決まった時点で、初めて古い鎖を捨てて新しい鎖にする
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
