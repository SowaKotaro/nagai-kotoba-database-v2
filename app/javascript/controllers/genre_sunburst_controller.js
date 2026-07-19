import { Controller } from "@hotwired/stimulus"

// ジャンル別の語義数(Plotly)。小分類が多くても破綻しないよう「1クリック=1階層」で掘り下げる:
//   - サンバーストは maxdepth: 2 で常に「中心+2階層」だけ描画する(小分類は中分類を
//     押したときに初めて現れる。ラベルが読め、ズームの再描画も軽い)
//   - 右は 大分類の積み上げ棒 → 押すとその大分類の中分類の積み上げ棒 → さらに押すと
//     その中分類の小分類を墨枠タグ(件数付き)の一覧で表示する
//   - 末端(小分類)は扇もタグも、そのジャンルで絞り込んだ語の一覧へ遷移する
// Plotly(vendor/javascript/plotly.min.js)はこのページ専用のため、接続時に1度だけ読み込む。
export default class extends Controller {
  static targets = ["data", "sunburst", "largeBar",
                    "mediumContainer", "mediumTitle", "mediumBar",
                    "smallContainer", "smallTitle", "smallList"]
  static values = { script: String, searchUrl: String, countLabel: String, smallsSuffix: String }

  // 朱の濃淡だけのパレット(--shu #C43A1E 起点。多色カテゴリカルは作らない)
  static palette = [
    "#C43A1E", "#CC5036", "#D4664E", "#DC7C66", "#E4927E",
    "#EBA896", "#F1BDAE", "#F6D0C5", "#F9E0D9", "#FBEDE8"
  ]

  async connect() {
    this.chartData = JSON.parse(this.dataTarget.textContent)
    this.plots = []
    await this.loadPlotly()
    this.renderSunburst()
    this.renderLargeBar()
  }

  disconnect() {
    if (window.Plotly) this.plots.forEach((element) => window.Plotly.purge(element))
  }

  // Plotly はサイズが大きいので importmap には載せず、必要になったこのページで1度だけ挿入する。
  loadPlotly() {
    if (window.Plotly) return Promise.resolve()
    if (!this.constructor.plotlyPromise) {
      this.constructor.plotlyPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script")
        script.src = this.scriptValue
        script.onload = resolve
        script.onerror = reject
        document.head.appendChild(script)
      })
    }
    return this.constructor.plotlyPromise
  }

  baseLayout() {
    return {
      paper_bgcolor: "transparent",
      plot_bgcolor: "transparent",
      font: { family: "'Shippori Mincho', 'Hiragino Mincho ProN', serif", size: 13 }
    }
  }

  plotConfig() {
    return { responsive: true, displayModeBar: false }
  }

  // --- データ参照(ids/parents の並列配列から) ---

  indexOf(id) {
    return this.chartData.ids.indexOf(id)
  }

  childrenOf(parentId) {
    return this.chartData.ids.filter((_, index) => this.chartData.parents[index] === parentId)
  }

  nodeOf(id) {
    const index = this.indexOf(id)
    return {
      id: id,
      genreId: this.chartData.genre_ids[index],
      label: this.chartData.labels[index],
      value: this.chartData.values[index]
    }
  }

  hoverTemplate(label) {
    return `<b>${label}</b><br>${this.countLabelValue}: %{value}<extra></extra>`
  }

  // --- サンバースト(クリックでその部分を全体として展開。Plotly 標準挙動) ---

  renderSunburst() {
    window.Plotly.newPlot(this.sunburstTarget, [ {
      type: "sunburst",
      ids: this.chartData.ids,
      labels: this.chartData.labels,
      parents: this.chartData.parents,
      values: this.chartData.values,
      customdata: this.chartData.genre_ids,
      branchvalues: "total",
      sort: false,
      rotation: 90,
      // 常に「中心+2階層」だけ描画する。初期表示は大分類+中分類で、小分類は
      // 中分類を押したときだけ現れる(全小分類を一度に描くとラベルが潰れ、重い)。
      maxdepth: 2,
      marker: { line: { width: 1, color: "#FAF8F3" } },
      textfont: { size: 12 },
      hovertemplate: `<b>%{label}</b><br>${this.countLabelValue}: %{value}<extra></extra>`
    } ], {
      ...this.baseLayout(),
      margin: { l: 0, r: 0, t: 10, b: 10 },
      sunburstcolorway: this.constructor.palette,
      extendsunburstcolorway: true
    }, this.plotConfig())
    this.plots.push(this.sunburstTarget)

    // 末端(小分類)はそれ以上展開できないため、絞り込み検索へ遷移する。
    this.sunburstTarget.on("plotly_sunburstclick", (event) => {
      const point = event.points[0]
      if (!point || this.chartData.parents.includes(point.id)) return true

      window.location.href = `${this.searchUrlValue}?genre_id=${point.customdata}`
      return false
    })
  }

  // --- 大分類の積み上げ棒(押すとその大分類の中分類を展開) ---

  renderLargeBar() {
    const largeIds = this.childrenOf("")
    // 積み上げは下から積まれるため、逆順にして先頭(最多)を上に置く。
    const traces = largeIds.slice().reverse().map((id) => {
      const node = this.nodeOf(id)
      return {
        x: [ "" ],
        y: [ node.value ],
        name: node.label,
        type: "bar",
        marker: {
          color: this.constructor.palette[largeIds.indexOf(id) % this.constructor.palette.length],
          line: { color: "#FAF8F3", width: 1.5 }
        },
        hovertemplate: this.hoverTemplate(node.label),
        customdata: [ id ]
      }
    })

    window.Plotly.newPlot(this.largeBarTarget, traces, {
      ...this.baseLayout(),
      barmode: "stack",
      showlegend: false,
      margin: { l: 4, r: 4, t: 4, b: 4 },
      xaxis: { visible: false },
      yaxis: { visible: false }
    }, this.plotConfig())
    this.plots.push(this.largeBarTarget)

    this.largeBarTarget.on("plotly_click", (event) => {
      const id = event.points[0].customdata
      if (id) this.expandLarge(id)
    })
  }

  // --- 選んだ大分類の中分類(積み上げ棒。押すとその中分類の小分類を展開) ---

  expandLarge(largeId) {
    const large = this.nodeOf(largeId)
    const mediumIds = this.childrenOf(largeId)

    this.mediumContainerTarget.hidden = false
    this.mediumTitleTarget.textContent = large.label
    // 大分類を切り替えたら、前の大分類の小分類一覧は閉じる(段階展開をやり直す)。
    this.smallContainerTarget.hidden = true
    const traces = mediumIds.slice().reverse().map((id) => {
      const node = this.nodeOf(id)
      return {
        x: [ "" ],
        y: [ node.value ],
        name: node.label,
        type: "bar",
        marker: {
          color: this.constructor.palette[(mediumIds.indexOf(id) * 2) % this.constructor.palette.length],
          line: { color: "#FAF8F3", width: 1.5 }
        },
        hovertemplate: this.hoverTemplate(node.label),
        customdata: [ id ]
      }
    })
    window.Plotly.react(this.mediumBarTarget, traces, {
      ...this.baseLayout(),
      barmode: "stack",
      showlegend: false,
      margin: { l: 4, r: 4, t: 4, b: 4 },
      xaxis: { visible: false },
      yaxis: { visible: false }
    }, this.plotConfig())
    if (!this.plots.includes(this.mediumBarTarget)) {
      this.plots.push(this.mediumBarTarget)
      // クリックハンドラは要素に1度だけ付ける(Plotly.react を跨いで生き続ける)。
      this.mediumBarTarget.on("plotly_click", (event) => {
        const id = event.points[0].customdata
        if (id) this.expandMedium(id)
      })
    }
  }

  // --- 選んだ中分類の小分類(墨枠タグ+件数の一覧。多くても縦に伸びず、そのまま検索導線) ---

  expandMedium(mediumId) {
    const medium = this.nodeOf(mediumId)
    const smallIds = this.childrenOf(mediumId)

    this.smallContainerTarget.hidden = false
    this.smallTitleTarget.textContent = `${medium.label}${this.smallsSuffixValue}`
    this.smallListTarget.replaceChildren(...smallIds.map((id) => {
      const node = this.nodeOf(id)
      const link = document.createElement("a")
      link.className = "tag genre-hub__small"
      link.href = `${this.searchUrlValue}?genre_id=${node.genreId}`
      link.append(node.label)
      const count = document.createElement("span")
      count.className = "genre-hub__count"
      count.textContent = node.value
      link.append(count)
      return link
    }))
  }
}
