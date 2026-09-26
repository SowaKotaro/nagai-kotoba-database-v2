import { Controller } from "@hotwired/stimulus"

// 押しても行の選択を切り替えない場所(リンク・ボタン・処理の選択・入力欄・行の中の「直す」フォーム)。
const INTERACTIVE = "a, button, input, label, select, textarea, summary, [contenteditable], .cand-choice, form"
// 文字を打つ場所(Space・Shift+↑↓・Esc を横取りしない)。
const EDITABLE = "input[type=text], input[type=search], input[type=number], textarea, [contenteditable]"
// なぞりの自動スクロールを始める、画面の上端・下端からの距離と、1コマで動かす上限(px)。
const SCROLL_EDGE = 48
const SCROLL_MAX_STEP = 24

// 一覧の行を選ぶ(登録予定単語の 仕分け・表記の確認・すべての語 で共用)。選んだ行は下端のバーでまとめて処理する。
// 行の左端の「選択の列」(label + checkbox)は行の高さいっぱいが当たり判定で、JS が無くても押せる。ここで足すのは:
// - 行のどこを押しても選択を切り替える(リンク・ボタン・処理の選択・入力欄の上は除く)
// - Shift+クリック: 直前に押した行から、押した行までをまとめて選ぶ(外した行なら、まとめて外す)
// - なぞり: 選択の列を押したまま上下になぞると、通った行をまとめて選ぶ(選んである行から始めると外す)。
//   画面の端(下端に貼り付くバーの上)まで来たら自動でスクロールする。Shift の無いスマホでは、これで範囲を取る
// - キーボード: Space で今の行を選ぶ、Shift+↑↓ で範囲を広げる(戻すと狭まる。Shift を離しても続けられる)、
//   Esc で選択を外す
// - 「すべて選ぶ」(見えている行)・「この系統を選ぶ」(data-row-group の中。すべて選んであれば外す)・「選択を外す」
// - 選んだ語数と、バーの切り替え(idle: 何も選んでいないとき / selecting: 選んでいるとき)
export default class extends Controller {
  static targets = ["row", "count", "idle", "selecting", "bar", "groupToggle"]
  static values = { selectedLabel: String }

  connect() {
    this.anchor = null
    // JS が無いと働かない操作(すべて選ぶ 等)は、接続してから見せる(data-js-only)
    this.element.dataset.rowSelectReady = ""
    this.sync()
  }

  disconnect() {
    this.endSweep()
  }

  // --- 押す ---

  // 選択の列を押したときにフォーカスと文字列の選択を動かさない。Shift+クリックで文字列の選択を広げない。
  mousedown(event) {
    const row = this.rowOf(event.target)
    if (!row || event.target.closest(EDITABLE)) return
    if (event.target.closest(".row-check") || event.shiftKey) event.preventDefault()
  }

  // 行を押したとき。選択の列(checkbox)ならもう切り替わっているので状態をそろえるだけ、行のほかの場所なら切り替える
  // (リンク・ボタン・処理の選択・入力欄の上と、文字列を選び終えたときは除く)。
  clicked(event) {
    if (this.sweptAt && event.timeStamp - this.sweptAt < 100) {
      // なぞり終えたときのクリックで、始めた行の checkbox が切り替わってしまうのを打ち消す
      this.sweptAt = null
      event.preventDefault()
      return
    }

    const row = this.rowOf(event.target)
    if (!row || !this.isSelectable(row)) return

    const checkbox = this.checkboxOf(row)
    if (event.target !== checkbox) {
      if (event.target.closest(INTERACTIVE) || this.hasTextSelection()) return
      checkbox.checked = !checkbox.checked
    }
    this.toggled(row, event.shiftKey)
  }

  // 1行を切り替えたあと。Shift を押していれば、直前に押した行からこの行までを同じ状態にそろえる。
  toggled(row, extend) {
    this.endSweep()
    if (extend && this.anchor && this.anchor !== row) {
      const rows = this.selectableRows()
      const from = rows.indexOf(this.anchor)
      const to = rows.indexOf(row)
      if (from >= 0 && to >= 0) {
        const selected = this.isSelected(row)
        rows.slice(Math.min(from, to), Math.max(from, to) + 1).forEach((target) => this.setSelected(target, selected))
      }
      window.getSelection()?.removeAllRanges()
    }
    this.anchor = row
    this.sync()
  }

  // --- なぞる(選択の列) ---

  pointerdown(event) {
    const gutter = event.target.closest(".row-check")
    const row = gutter && this.rowOf(gutter)
    if (!row || event.button !== 0 || !this.isSelectable(row)) return
    if (!this.beginSweep(row, !this.isSelected(row))) return

    this.dragging = true
    // 左右のぶれは見ず、選択の列の中ほどを縦になぞったものとして行を探す
    const rect = gutter.getBoundingClientRect()
    this.pointer = { x: rect.left + rect.width / 2, y: event.clientY }
    try {
      gutter.setPointerCapture(event.pointerId)
    } catch {
      // 捕まえられないポインタ(合成したイベントなど)は、捕まえずに進める
    }
  }

  pointermove(event) {
    if (!this.dragging) return

    this.pointer.y = event.clientY
    this.sweepAt(this.pointer.y)
    this.autoScroll()
  }

  pointerup() {
    if (!this.dragging) return

    if (this.sweep.moved) {
      this.sweptAt = performance.now()
      this.anchor = this.sweep.rows[this.sweep.current]
    }
    this.endSweep()
  }

  // 高さ y にある行まで塗る。始めた行から動いていなければ何もしない(ただのタップは clicked に任せる)。
  sweepAt(y) {
    const element = document.elementFromPoint(this.pointer.x, y)
    const index = element ? this.sweep.rows.indexOf(this.rowOf(element)) : -1
    if (index < 0 || (!this.sweep.moved && index === this.sweep.start)) return

    this.sweep.moved = true
    this.sweepTo(index)
  }

  // なぞりが画面の上端・下端に近づいたら、近さに応じて少しずつスクロールしながら塗り続ける。
  autoScroll() {
    if (this.scrollFrame) return

    const step = () => {
      this.scrollFrame = null
      if (!this.dragging) return

      const y = this.pointer.y
      const bottom = this.visibleBottom() - SCROLL_EDGE
      const distance = y < SCROLL_EDGE ? y - SCROLL_EDGE : y > bottom ? y - bottom : 0
      if (distance === 0) return

      window.scrollBy(0, Math.sign(distance) * Math.min(SCROLL_MAX_STEP, Math.ceil(Math.abs(distance) / 3)))
      this.sweepAt(y)
      this.scrollFrame = requestAnimationFrame(step)
    }
    this.scrollFrame = requestAnimationFrame(step)
  }

  // 一覧が見えている下端。下端に貼り付いているバーがあれば、その上端。
  visibleBottom() {
    if (!this.hasBarTarget) return window.innerHeight

    const rect = this.barTarget.getBoundingClientRect()
    return rect.bottom >= window.innerHeight - 1 ? rect.top : window.innerHeight
  }

  // --- 範囲を塗る(なぞり・Shift+↑↓ で共用) ---

  // row から始めて、paint(選ぶ / 外す)で塗っていく。始めたときの選択を覚えておき、範囲の外はそれに戻す。
  beginSweep(row, paint) {
    const rows = this.selectableRows()
    const start = rows.indexOf(row)
    if (start < 0) return null

    this.sweep = { rows, start, current: start, paint, snapshot: rows.map((target) => this.isSelected(target)), moved: false }
    return this.sweep
  }

  // 始めた行から index の行までを塗る(行き過ぎて戻れば、範囲が狭まる)。
  sweepTo(index) {
    const { rows, start, paint, snapshot } = this.sweep
    const from = Math.min(start, index)
    const to = Math.max(start, index)
    rows.forEach((row, i) => this.setSelected(row, i >= from && i <= to ? paint : snapshot[i]))
    this.sweep.current = index
    this.sync()
  }

  endSweep() {
    if (this.scrollFrame) cancelAnimationFrame(this.scrollFrame)
    this.scrollFrame = null
    this.sweep = null
    this.dragging = false
  }

  // --- キーボード(window で受ける。フォーカスが行の外にあっても Esc で外せるように) ---

  keydown(event) {
    if (event.key === "Escape") {
      this.escape(event)
      return
    }
    if (event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return

    const row = this.rowOf(event.target)
    if (!row || event.target.closest(EDITABLE)) return

    if (event.key === " " && event.target !== this.checkboxOf(row) && !event.target.closest("a, button")) {
      // 処理のラジオなどにいるとき、Space で行を選ぶ(checkbox にいるときはブラウザの既定で切り替わる)
      event.preventDefault()
      if (!this.isSelectable(row)) return
      this.endSweep()
      this.setSelected(row, !this.isSelected(row))
      this.anchor = row
      this.sync()
    } else if (event.shiftKey && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
      event.preventDefault()
      this.extendByKey(row, event.key === "ArrowDown" ? 1 : -1)
    }
  }

  // Shift+↑↓: 今の行から始め、押すたびに隣の行まで範囲を広げる(戻すと狭まる)。フォーカスも隣の行へ動かす。
  // 前の Shift+↑↓ で着いた行から続けて押したときは、同じ範囲を広げ直す(Shift を一度離しても続けられる)。
  // ほかの操作で選択を変えたり、↑↓ で別の行へ移ったりしたら、そこから新しく始める。
  extendByKey(row, step) {
    const continuing = this.sweep && !this.dragging && this.sweep.rows[this.sweep.current] === row
    if (!continuing) {
      if (!this.beginSweep(row, true)) return
      this.sweepTo(this.sweep.start)
    }
    const next = this.sweep.current + step
    if (next < 0 || next >= this.sweep.rows.length) return

    this.sweepTo(next)
    this.anchor = this.sweep.rows[next]
    this.focusRow(this.anchor)
  }

  // Esc: 選んでいる行があれば、すべて外す(行の中で「直す」を開いているときは、そちらの取りやめに任せる)。
  escape(event) {
    if (event.target.closest?.(`${EDITABLE}, turbo-frame form`)) return
    if (!this.rowTargets.some((row) => this.isSelected(row))) return

    event.preventDefault()
    this.clear()
  }

  // --- まとめて ---

  // 見えている行(絞り込みで隠した行・畳んだ欄の中の行を除く)をすべて選ぶ。
  selectAll() {
    this.endSweep()
    this.selectableRows().forEach((row) => this.setSelected(row, true))
    this.sync()
  }

  // 系統の見出しの「この系統を選ぶ」: その系統の見えている行をすべて選ぶ(すべて選んであれば外す)。
  toggleGroup(event) {
    this.endSweep()
    const group = event.currentTarget.closest("[data-row-group]")
    const rows = this.selectableRows().filter((row) => group?.contains(row))
    const select = !rows.every((row) => this.isSelected(row))
    rows.forEach((row) => this.setSelected(row, select))
    if (rows.length > 0) this.anchor = rows[rows.length - 1]
    this.sync()
  }

  clear() {
    this.endSweep()
    this.rowTargets.forEach((row) => this.setSelected(row, false))
    this.anchor = null
    this.sync()
  }

  // --- 内部 ---

  // 行の data-selected(見た目)・選んだ語数・バーの切り替え・系統の見出しのボタンの状態をそろえる。
  sync() {
    let count = 0
    this.rowTargets.forEach((row) => {
      const selected = this.isSelected(row)
      row.dataset.selected = selected
      if (selected) count += 1
    })

    const label = this.selectedLabelValue.replace("%{count}", count)
    this.countTargets.forEach((element) => { element.textContent = label })
    this.idleTargets.forEach((element) => { element.hidden = count > 0 })
    this.selectingTargets.forEach((element) => { element.hidden = count === 0 })
    this.groupToggleTargets.forEach((button) => {
      const group = button.closest("[data-row-group]")
      const rows = this.rowTargets.filter((row) => group?.contains(row) && this.isSelectable(row))
      button.setAttribute("aria-pressed", String(rows.length > 0 && rows.every((row) => this.isSelected(row))))
    })
  }

  isSelected(row) {
    return this.checkboxOf(row)?.checked === true
  }

  isSelectable(row) {
    const checkbox = this.checkboxOf(row)
    return Boolean(checkbox) && !checkbox.disabled
  }

  setSelected(row, selected) {
    if (!this.isSelectable(row)) return

    this.checkboxOf(row).checked = selected
    row.dataset.selected = selected
  }

  checkboxOf(row) {
    return row.querySelector(".row-check input[type=checkbox]")
  }

  rowOf(element) {
    const row = element?.closest?.("[data-row-select-target~='row']")
    return row && this.element.contains(row) ? row : null
  }

  // 選べる行(絞り込みで隠した行・畳んだ欄の中の行・選べない行を除く)を、並んでいる順に。
  selectableRows() {
    return this.rowTargets.filter((row) => row.offsetParent !== null && this.isSelectable(row))
  }

  // 行へフォーカスを移す(処理のラジオがあればそれ、なければ選択の checkbox)。
  focusRow(row) {
    const target = row.querySelector("input[type=radio]:checked") || this.checkboxOf(row)
    target?.focus({ preventScroll: true })
    row.scrollIntoView({ block: "nearest" })
  }

  hasTextSelection() {
    const selection = window.getSelection()
    return Boolean(selection) && !selection.isCollapsed && selection.toString().trim() !== ""
  }
}
