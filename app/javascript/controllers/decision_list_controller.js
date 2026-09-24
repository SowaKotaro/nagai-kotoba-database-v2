import { Controller } from "@hotwired/stimulus"

// 登録予定単語の確認の一覧(仕分け・表記の確認)で、語ごとの処理(拡張 / 採用 / 保留 / 除外)を選ぶ操作を速くする。
// 選択そのものはラジオなので、JS が無くても選んで確定できる。ここで足すのは次のとおり:
// - 件数: 選択が変わるたびに、下端のバーの処理ごとの語数を数え直す(行の data-decision も合わせる)
// - キーボード: ↑↓(Enter / Shift+Enter)で行を移る。行のキー(ラジオの data-key)で処理を選ぶと次の行へ進む。
//   ←→ はラジオの標準のまま(同じ行の中で選び直す)。Ctrl+Enter(Mac は ⌘+Enter)で確定する
// - Shift+クリック: 直前に選んだ行からその行までを、同じ処理にそろえる
// - まとめて: 系統の見出しのボタンで、その系統の見えている行をそろえる
// - 絞り込み: 印(重複の疑い 等)で行を絞る。隠れた行も、選んである処理のまま一緒に確定される
// - 手直し: F2 で行の「直す」を開き、Esc で取りやめる。行に戻ったら、その行の選択にフォーカスを戻す
export default class extends Controller {
  static targets = ["row", "count", "filter"]
  static values = { form: String }

  connect() {
    // 範囲選択の起点(直前に選んだ行)
    this.anchor = null
    this.refreshCounts()
    this.focusFirstRow()
  }

  // ラジオを選び直した(クリック・タップ・←→)。
  changed(event) {
    const input = this.decisionInput(event.target)
    if (!input) return

    const row = this.rowOf(input)
    row.dataset.decision = input.value
    this.anchor = row
    this.refreshCounts()
  }

  // Shift+クリックで、起点の行からクリックした行までを同じ処理にそろえる。
  // クリックした行そのものの選択はブラウザの既定の動作に任せる(ここで先に選んでおくので change は出ない)。
  clicked(event) {
    if (!event.shiftKey || !this.anchor) return

    const option = event.target.closest(".cand-choice__option")
    const input = option?.querySelector("input[type=radio]")
    if (!input) return

    const rows = this.visibleRows()
    const row = this.rowOf(input)
    const from = rows.indexOf(this.anchor)
    const to = rows.indexOf(row)
    if (from < 0 || to < 0) return

    rows.slice(Math.min(from, to), Math.max(from, to) + 1).forEach((target) => this.choose(target, input.value))
    this.anchor = row
    this.refreshCounts()
  }

  keydown(event) {
    if (event.key === "Escape" && this.cancelEdit(event.target)) return

    const input = this.decisionInput(event.target)
    if (!input || event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return

    const row = this.rowOf(input)
    if (event.key === "F2") {
      event.preventDefault()
      row.querySelector(".cand-word__edit")?.click()
    } else if (event.key === "ArrowDown" || (event.key === "Enter" && !event.shiftKey)) {
      event.preventDefault()
      this.focusRow(row, 1)
    } else if (event.key === "ArrowUp" || (event.key === "Enter" && event.shiftKey)) {
      event.preventDefault()
      this.focusRow(row, -1)
    } else if (event.key.length === 1) {
      const target = row.querySelector(`input[type=radio][data-key="${CSS.escape(event.key.toLowerCase())}"]`)
      if (!target) return

      event.preventDefault()
      this.choose(row, target.value)
      this.anchor = row
      this.refreshCounts()
      this.focusRow(row, 1)
    }
  }

  // 系統の見出し(data-decision-scope)のボタン: その系統の見えている行を、ボタンの処理にそろえる。
  applyToScope(event) {
    const scope = event.currentTarget.closest("[data-decision-scope]") || this.element
    const value = event.currentTarget.dataset.decision
    this.visibleRows().filter((row) => scope.contains(row)).forEach((row) => this.choose(row, value))
    this.refreshCounts()
  }

  // 印で行を絞る(data-flag が空なら全部を出す)。行が1つも見えない系統は見出しごと隠す。
  filter(event) {
    const flag = event.currentTarget.dataset.flag
    this.filterTargets.forEach((chip) => chip.setAttribute("aria-pressed", String(chip === event.currentTarget)))
    this.rowTargets.forEach((row) => {
      row.hidden = flag !== "" && !row.dataset.flags.split(" ").includes(flag)
    })
    this.element.querySelectorAll("[data-decision-scope]").forEach((scope) => {
      scope.hidden = !this.rowTargets.some((row) => !row.hidden && scope.contains(row))
    })
  }

  // 行の「語」の部分(turbo-frame)が表示に戻ったら、その行の選択にフォーカスを戻す(キーボードで続けられるように)。
  frameRendered(event) {
    const row = event.target.closest("[data-decision-list-target~='row']")
    if (!row || event.target.querySelector("form")) return

    row.querySelector("input[type=radio]:checked")?.focus({ preventScroll: true })
  }

  // Ctrl+Enter(⌘+Enter)で確定する。貼り付け欄などの入力中は、その欄のフォームに任せる。
  submitShortcut(event) {
    if (event.key !== "Enter" || !(event.ctrlKey || event.metaKey) || event.defaultPrevented) return
    if (event.target instanceof Element && event.target.closest("textarea, input[type=text], input[type=search]")) return

    event.preventDefault()
    document.getElementById(this.formValue)?.requestSubmit()
  }

  // --- 内部 ---

  // 行の中で開いた「直す」を Esc で取りやめる(取りやめのリンクを押したのと同じ)。
  cancelEdit(target) {
    const cancel = target instanceof Element && target.closest("turbo-frame")?.querySelector(".cand-edit__cancel")
    if (!cancel) return false

    cancel.click()
    return true
  }

  choose(row, value) {
    const input = row.querySelector(`input[type=radio][value="${CSS.escape(value)}"]`)
    if (!input) return

    input.checked = true
    row.dataset.decision = value
  }

  refreshCounts() {
    const tally = {}
    this.rowTargets.forEach((row) => {
      tally[row.dataset.decision] = (tally[row.dataset.decision] || 0) + 1
    })
    this.countTargets.forEach((count) => {
      count.textContent = tally[count.dataset.decision] || 0
    })
  }

  // 開いてすぐ ↓ や処理のキーで始められるよう、どこにもフォーカスが無く、先頭の行が画面に見えていればそこに置く
  // (見えていない行に置くと、キーを押したときに知らないうちに選び直してしまうため)。
  // タッチの端末ではキーで操作しないので置かない(先頭の行だけが強調されて見えるのを避ける)。
  focusFirstRow() {
    if (window.matchMedia("(hover: none)").matches) return
    if (document.activeElement && document.activeElement !== document.body) return

    const first = this.visibleRows()[0]
    if (!first || first.getBoundingClientRect().bottom > window.innerHeight) return

    first.querySelector("input[type=radio]:checked")?.focus({ preventScroll: true })
  }

  // 次(step=1)・前(step=-1)の見えている行へ移る。移った先では選んである処理のラジオにフォーカスする
  // (ラジオの組は Tab で1回ずつ止まり、←→で選び直せる)。下端のバーに隠れないよう行ごと見せる。
  focusRow(row, step) {
    const rows = this.visibleRows()
    const next = rows[rows.indexOf(row) + step]
    if (!next) return

    const input = next.querySelector("input[type=radio]:checked") || next.querySelector("input[type=radio]")
    input.focus({ preventScroll: true })
    next.scrollIntoView({ block: "nearest" })
  }

  // 絞り込みで隠した行と、畳んだ欄(保留)の中の行を除く。
  visibleRows() {
    return this.rowTargets.filter((row) => row.offsetParent !== null)
  }

  rowOf(input) {
    return input.closest("[data-decision-list-target~='row']")
  }

  decisionInput(target) {
    return target instanceof HTMLInputElement && target.type === "radio" && this.rowOf(target) ? target : null
  }
}
