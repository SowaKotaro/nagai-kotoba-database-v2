import { Controller } from "@hotwired/stimulus"

// 統計ページ「ジャンル別の語義数」(docs/stats.md §5)。大→中→小の 3 階層を、インライン SVG のサンバーストと、
// いま見ている階層の内訳(名前・語義数・割合・横棒の行。小分類は件数つきのタグ)で見せる。
//   - サンバーストは常に「中心+2 階層」だけ描く(小分類は中分類を押したときに初めて現れる)
//   - 扇か行を押すと、その分類を中心にして 1 階層掘り下げる。中心かパンくずで戻る。円と内訳は同じ状態を共有する
//   - 末端(小分類)は扇もタグも、そのジャンルで絞り込んだ単語一覧へ移る
//   - 掘り下げは、押した扇が全体へ広がり、ほかが両脇へ畳まれる動きで見せる(prefers-reduced-motion では切り替えるだけ)
// 使う画面は /stats だけ。データはサーバが JSON で埋め込み、行・タグ・パンくずは <template> から複製する。
// JS が無いと図も内訳も出ず、noscript の注記だけが出る。ほかのコントローラとの連携は無い
// (色は CSS のトークンで塗るので、theme:change を受けなくてもダークに追従する)。
const SVG_NS = "http://www.w3.org/2000/svg"

// 図の座標(viewBox の単位)。中心の円・1 階層目と 2 階層目の境・外周の半径
const SIZE = 440
const CENTER = SIZE / 2
const HUB = 64
const MID = 142
const OUTER = 218

// 塗りは --chart のチントで、きょうだいの中の順位で濃さを決める(単位は %)。
// 上限は上に字を載せられる濃さ(docs/stats.md §1)、下限は札の白との差 ΔRGB 19 を割らない濃さ
const TINT_MAX = 45
const TINT_MIN = 16

// 扇のラベル(画面上の px。図が縮んでも字は縮めず、入らない扇のラベルを落とす)
const LABEL_SIZE = 12
const LABEL_PAD = 6
const LABEL_LINE = 15
const LABEL_TRACKING = 0.04 // em。components.css の .genre-sunburst__label の letter-spacing と同じ
const HALF_WIDTH = 0.58 // 半角 1 字の幅(em)の見積もり
const HUB_LINES = 3

// 掘り下げの動き。置き換える前の Plotly の感触に寄せた長さと緩急(cubic-in-out)
const ZOOM_MS = 750

export default class extends Controller {
  static targets = [ "data", "figure", "crumbs", "rows",
                     "crumbTemplate", "currentTemplate", "rowTemplate", "tagTemplate" ]
  static values = { searchUrl: String, rootLabel: String, backLabel: String }

  connect() {
    this.buildTree(JSON.parse(this.dataTarget.textContent))
    this.focus = this.root
    this.figureTarget.setAttribute("viewBox", `0 0 ${SIZE} ${SIZE}`)
    this.drawFigure()
    this.drawDetail()
  }

  disconnect() {
    this.stopZoom()
  }

  // ── 操作 ──────────────────────────────────────────────────────────

  // 扇・行・パンくずを押した。子を持つ分類なら掘り下げ、末端なら単語一覧へ移る
  open(event) {
    const node = this.nodes.get(event.params.key)
    if (!node) return
    if (node.children.length === 0) {
      window.location.href = this.searchUrlFor(node)
      return
    }

    // 行やパンくずをキーボードで押したときに、作り直した内訳の先頭へフォーカスを渡す(扇はフォーカスを持たない)
    const fromDetail = event.currentTarget instanceof HTMLElement
    this.show(node)
    if (fromDetail) this.rowsTarget.querySelector("a, button")?.focus()
  }

  // 中心を押した。1 階層戻る
  up() {
    if (this.focus.parent) this.show(this.focus.parent)
  }

  // 扇と、その内訳の行(タグ)を一緒に示す。2 階層目の扇は親の行を示す
  heat(event) {
    this.toggleHot(event.currentTarget.dataset.row, true)
  }

  cool(event) {
    this.toggleHot(event.currentTarget.dataset.row, false)
  }

  // 幅が変わったら、ラベルの入り方を決め直す(字は画面上の大きさを保つ)
  resize() {
    if (this.frame || this.unit === this.measureUnit()) return
    this.drawFigure()
  }

  // ── データ ────────────────────────────────────────────────────────

  // サーバの入れ子([{ id, name, count, children }]。多い順)を、親・深さ・持ち場つきの木にする。
  // 持ち場(x0〜x1)は全体を 0〜1 とした角度の割り当てで、掘り下げの動きはこれを新旧の中心で測り直して補間する
  buildTree(groups) {
    this.nodes = new Map()
    this.root = { key: "root", label: this.rootLabelValue, parent: null, depth: 0, shade: 0, children: [] }
    this.root.value = groups.reduce((sum, group) => sum + group.count, 0)
    this.nodes.set(this.root.key, this.root)
    this.place(this.root, groups, 0)
  }

  place(parent, items, x0) {
    parent.x0 = x0
    parent.x1 = x0 + parent.value / this.root.value
    let x = x0
    items.forEach((item, index) => {
      const node = {
        key: `${parent.depth + 1}-${item.id}`, genreId: item.id, label: item.name, value: item.count,
        parent: parent, depth: parent.depth + 1, shade: this.shade(index, items.length), children: []
      }
      this.nodes.set(node.key, node)
      parent.children.push(node)
      this.place(node, item.children || [], x)
      x = node.x1
    })
  }

  shade(index, count) {
    if (count <= 1) return TINT_MAX
    return TINT_MAX - (TINT_MAX - TINT_MIN) * index / (count - 1)
  }

  searchUrlFor(node) {
    return `${this.searchUrlValue}?genre_id=${node.genreId}`
  }

  format(value) {
    return value.toLocaleString(document.documentElement.lang || undefined)
  }

  // ── 切り替え ──────────────────────────────────────────────────────

  show(node) {
    const from = this.focus
    this.focus = node
    this.stopZoom()
    this.drawDetail()
    if (from === node || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.drawFigure()
    } else {
      this.zoom(from, node)
    }
  }

  toggleHot(row, on) {
    if (!row) return
    this.element.querySelectorAll(`[data-row="${row}"]`).forEach((element) => element.classList.toggle("is-hot", on))
  }

  // ── 幾何 ──────────────────────────────────────────────────────────

  point(radius, degrees) {
    const radians = degrees * Math.PI / 180
    return `${(CENTER + radius * Math.cos(radians)).toFixed(2)},${(CENTER + radius * Math.sin(radians)).toFixed(2)}`
  }

  // from → to の円弧。to < from なら反時計回り
  arc(radius, from, to) {
    const large = Math.abs(to - from) > 180 ? 1 : 0
    const sweep = to > from ? 1 : 0
    return `A${radius},${radius} 0 ${large} ${sweep} ${this.point(radius, to)}`
  }

  wedgePath(inner, outer, from, to) {
    return `M${this.point(outer, from)} ${this.arc(outer, from, to)} L${this.point(inner, to)} ${this.arc(inner, to, from)} Z`
  }

  // 1 周する扇は始点と終点が重なって円弧が消えるので、わずかに手前で止める
  capped(from, to) {
    return Math.min(to, from + 359.99)
  }

  isDeep(center) {
    return center.children.some((child) => child.children.length > 0)
  }

  // center を中心にしたときの node の形。視野の外の分類は、角度が両端に、半径が中心か外周に畳まれる
  geometry(node, center) {
    const width = center.x1 - center.x0
    const clamp = (x) => Math.min(Math.max((x - center.x0) / width, 0), 1)
    const depth = node.depth - center.depth
    let radii = [ OUTER, OUTER ]
    if (depth < 0) radii = [ 0, 0 ]
    else if (depth === 0) radii = [ 0, HUB ]
    else if (depth === 1) radii = [ HUB, this.isDeep(center) ? MID : OUTER ]
    else if (depth === 2 && this.isDeep(center)) radii = [ MID, OUTER ]

    return {
      from: clamp(node.x0) * 360 - 90, to: clamp(node.x1) * 360 - 90,
      inner: radii[0], outer: radii[1], shade: depth === 0 ? 0 : node.shade
    }
  }

  // ── 図 ────────────────────────────────────────────────────────────

  svg(name, attributes = {}, text) {
    const element = document.createElementNS(SVG_NS, name)
    Object.entries(attributes).forEach(([ key, value ]) => element.setAttribute(key, value))
    if (text !== undefined) element.textContent = text
    return element
  }

  // viewBox の 1 単位が画面の何 px の逆数か(図が縮むほど大きい)。画面上の px を viewBox の長さへ直すのに掛ける
  measureUnit() {
    const width = this.figureTarget.getBoundingClientRect().width
    return width > 0 ? Math.round(SIZE / width * 100) / 100 : 1
  }

  drawFigure() {
    this.unit = this.measureUnit()
    this.figureTarget.style.setProperty("--label-size", `${(LABEL_SIZE * this.unit).toFixed(2)}px`)
    this.arcSerial = 0

    const defs = this.svg("defs")
    const shapes = this.svg("g")
    const labels = this.svg("g", { class: "genre-sunburst__labels" })
    const ringOuter = this.isDeep(this.focus) ? MID : OUTER
    this.focus.children.forEach((child) => {
      const shape = this.geometry(child, this.focus)
      shapes.append(this.wedge(child, HUB, ringOuter, shape.from, shape.to, child.key))
      this.label(labels, defs, child, HUB, ringOuter, shape.from, this.capped(shape.from, shape.to))
      child.children.forEach((grandchild) => {
        const inner = this.geometry(grandchild, this.focus)
        shapes.append(this.wedge(grandchild, MID, OUTER, inner.from, inner.to, child.key))
        this.label(labels, defs, grandchild, MID, OUTER, inner.from, this.capped(inner.from, inner.to))
      })
    })
    this.figureTarget.replaceChildren(defs, shapes, labels, ...this.hub())
    return labels
  }

  wedge(node, inner, outer, from, to, row) {
    return this.svg("path", {
      class: "genre-sunburst__wedge", d: this.wedgePath(inner, outer, from, this.capped(from, to)),
      style: `--t: ${node.shade.toFixed(1)}`, "data-row": row, "data-genre-sunburst-key-param": node.key,
      "data-action": "click->genre-sunburst#open mouseenter->genre-sunburst#heat mouseleave->genre-sunburst#cool"
    })
  }

  // 中心: いま見ている分類の名前と語義数。掘り下げているときは、押すと 1 階層戻る
  hub() {
    const up = this.focus !== this.root
    const circle = this.svg("circle", { class: "genre-sunburst__hub", cx: CENTER, cy: CENTER, r: HUB - 1 })
    if (up) circle.setAttribute("data-action", "click->genre-sunburst#up")

    const line = (LABEL_SIZE + 4) * this.unit
    const countHeight = 30
    const names = this.wrap(this.focus.label, Math.floor((HUB * 2 - 16) / (LABEL_SIZE * this.unit)), HUB_LINES)
    let y = CENTER - (names.length * line + countHeight + (up ? line : 0)) / 2 + line / 2
    const texts = names.map((name) => {
      const text = this.centered("genre-sunburst__hub-name", y, name)
      y += line
      return text
    })
    texts.push(this.centered("genre-sunburst__hub-count", y - line / 2 + countHeight / 2, this.format(this.focus.value)))
    if (up) texts.push(this.centered("genre-sunburst__hub-hint", y - line / 2 + countHeight + line / 2, this.backLabelValue))
    return [ circle, ...texts ]
  }

  centered(className, y, text) {
    return this.svg("text", { class: className, x: CENTER, y: y.toFixed(1), "text-anchor": "middle", "dominant-baseline": "central" }, text)
  }

  // 中黒の後ろを優先して、1 行 perLine 字で折る。maxLines を超えたら最後の行を「…」で詰める
  wrap(text, perLine, maxLines) {
    const lines = [ [] ]
    text.split(/(?<=・)/).forEach((token) => {
      const chars = [ ...token ]
      chars.forEach((char, index) => {
        const current = lines[lines.length - 1]
        const tokenOverflows = index === 0 && current.length > 0 && current.length + chars.length > perLine
        if (tokenOverflows || current.length >= perLine) lines.push([ char ])
        else current.push(char)
      })
    })
    const kept = lines.slice(0, maxLines).map((line) => line.join(""))
    if (lines.length > maxLines) kept[maxLines - 1] = `${[ ...kept[maxLines - 1] ].slice(0, perLine - 1).join("")}…`
    return kept
  }

  // ── 扇のラベル ────────────────────────────────────────────────────

  // 字の幅の見積もり(viewBox の単位)。全角 1em・半角 HALF_WIDTH に字間を足す
  charWidth(char) {
    const em = char.codePointAt(0) > 0x2e7f ? 1 : HALF_WIDTH
    return (em + LABEL_TRACKING) * LABEL_SIZE * this.unit
  }

  textWidth(text) {
    return [ ...text ].reduce((sum, char) => sum + this.charWidth(char), 0)
  }

  // room に収まるように「…」で詰める。2 字も残らないなら置かない(null)
  fit(text, room) {
    if (this.textWidth(text) <= room) return text

    let width = this.charWidth("…")
    let kept = ""
    for (const char of text) {
      if (width + this.charWidth(char) > room) break
      width += this.charWidth(char)
      kept += char
    }
    return [ ...kept ].length >= 2 ? `${kept}…` : null
  }

  // 弧に沿わせる(幅の広い扇)か、放射に置く(細い扇)かを、入る長さの大きい方で決める。
  // 名前の下に語義数を添えるのは 2 行ぶんの余地があるときだけ。入らない扇には置かない(数は内訳の行が持つ)
  label(group, defs, node, inner, outer, from, to) {
    const pad = LABEL_PAD * this.unit
    const line = LABEL_LINE * this.unit
    const middle = (inner + outer) / 2
    const span = (to - from) * Math.PI / 180
    const angle = (from + to) / 2
    const along = middle * span - pad * 2
    const across = outer - inner - pad * 2
    if (middle * span < line) return

    const count = [ this.format(node.value), "genre-sunburst__label genre-sunburst__label--count" ]
    if (along >= across) {
      // 内側の行は弧が短いので、その長さで詰める
      const name = this.fit(node.label, (middle - line / 2) * span - pad * 2)
      const lines = name && across >= line * 2 ? [ [ name, "genre-sunburst__label" ], count ] : [ name ? [ name, "genre-sunburst__label" ] : count ]
      if (this.textWidth(lines[lines.length - 1][0]) > along) return

      // 下半分は逆向きの弧に沿わせて、字が逆さにならないようにする(上の行が内側に来る)
      const lower = Math.sin(angle * Math.PI / 180) > 0
      lines.forEach(([ text, className ], index) => {
        const radius = middle + (index - (lines.length - 1) / 2) * line * (lower ? 1 : -1)
        const id = `genre-sunburst-arc-${this.arcSerial += 1}`
        const [ start, end ] = lower ? [ to, from ] : [ from, to ]
        defs.append(this.svg("path", { id: id, d: `M${this.point(radius, start)} ${this.arc(radius, start, end)}` }))
        const element = this.svg("text", { class: className, "text-anchor": "middle", "dominant-baseline": "central" })
        element.append(this.svg("textPath", { href: `#${id}`, startOffset: "50%" }, text))
        group.append(element)
      })
      return
    }

    const name = this.fit(node.label, across)
    if (!name) return

    // 左半分は 180° 回して、字が逆さにならないようにする
    const rotation = Math.cos(angle * Math.PI / 180) < 0 ? angle + 180 : angle
    const lines = middle * span >= line * 2 + 2 * this.unit ? [ [ name, "genre-sunburst__label" ], count ] : [ [ name, "genre-sunburst__label" ] ]
    lines.forEach(([ text, className ], index) => {
      const shift = (index - (lines.length - 1) / 2) * line
      group.append(this.svg("text", {
        class: className, "text-anchor": "middle", "dominant-baseline": "central",
        transform: `translate(${this.point(middle, angle)}) rotate(${rotation.toFixed(2)}) translate(0,${shift.toFixed(2)})`
      }, text))
    })
  }

  // ── 掘り下げの動き ────────────────────────────────────────────────

  // 新旧どちらかで見えている扇を、形と濃さを補間しながら描く。ラベルは動かさず、止まってから出す
  zoom(from, to) {
    const visible = (shape) => shape.to - shape.from > 0.01 && shape.outer - shape.inner > 0.01
    const moving = []
    this.nodes.forEach((node) => {
      const before = this.geometry(node, from)
      const after = this.geometry(node, to)
      if (visible(before) || visible(after)) moving.push({ before, after, path: this.svg("path", { class: "genre-sunburst__wedge" }) })
    })
    const shapes = this.svg("g")
    moving.forEach((item) => shapes.append(item.path))
    this.figureTarget.replaceChildren(shapes)

    const started = performance.now()
    const step = (now) => {
      const progress = Math.min((now - started) / ZOOM_MS, 1)
      const eased = progress < 0.5 ? 4 * progress ** 3 : 1 - (-2 * progress + 2) ** 3 / 2
      const mix = (a, b) => a + (b - a) * eased
      moving.forEach(({ before, after, path }) => {
        const start = mix(before.from, after.from)
        // 半径 0 の円弧はパスにならないので、わずかに残す
        path.setAttribute("d", this.wedgePath(Math.max(mix(before.inner, after.inner), 0.01), Math.max(mix(before.outer, after.outer), 0.02),
                                              start, this.capped(start, mix(before.to, after.to))))
        path.style.setProperty("--t", mix(before.shade, after.shade).toFixed(1))
      })
      if (progress < 1) {
        this.frame = requestAnimationFrame(step)
        return
      }
      this.frame = null
      this.drawFigure().classList.add("is-entering")
    }
    this.frame = requestAnimationFrame(step)
  }

  stopZoom() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
  }

  // ── 内訳(パンくず・行・タグ) ──────────────────────────────────────

  drawDetail() {
    const trail = []
    for (let node = this.focus; node; node = node.parent) trail.unshift(node)
    this.crumbsTarget.replaceChildren(...trail.map((node) => this.crumb(node)))

    // 末端だけの階層(小分類)は、多くても縦に伸びないように件数つきのタグで並べる
    const children = this.focus.children
    const tags = children.every((child) => child.children.length === 0)
    this.rowsTarget.classList.toggle("genre-rows--tags", tags)
    this.rowsTarget.replaceChildren(...children.map((child) => tags ? this.tag(child) : this.row(child, children[0].value)))
  }

  crumb(node) {
    const current = node === this.focus
    const item = (current ? this.currentTemplateTarget : this.crumbTemplateTarget).content.firstElementChild.cloneNode(true)
    const holder = item.firstElementChild
    holder.textContent = node.label
    if (!current) holder.setAttribute("data-genre-sunburst-key-param", node.key)
    return item
  }

  row(node, max) {
    const item = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
    const button = item.firstElementChild
    button.dataset.row = node.key
    button.setAttribute("data-genre-sunburst-key-param", node.key)
    this.fill(item, "name", node.label)
    this.fill(item, "count", this.format(node.value))
    this.fill(item, "share", (node.value / this.focus.value * 100).toFixed(1))
    const bar = item.querySelector("[data-field=bar]")
    bar.style.width = `${Math.max(node.value / max * 100, 1)}%`
    bar.style.setProperty("--t", node.shade.toFixed(1))
    return item
  }

  tag(node) {
    const item = this.tagTemplateTarget.content.firstElementChild.cloneNode(true)
    const link = item.firstElementChild
    link.href = this.searchUrlFor(node)
    link.dataset.row = node.key
    this.fill(item, "name", node.label)
    this.fill(item, "count", this.format(node.value))
    return item
  }

  fill(item, field, text) {
    item.querySelector(`[data-field=${field}]`).textContent = text
  }
}
