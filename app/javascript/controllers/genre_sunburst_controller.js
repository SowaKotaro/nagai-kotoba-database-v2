import { Controller } from "@hotwired/stimulus"

// ジャンル別の語義数(Plotly)。オーナー実装の「先頭/末尾文字分析」と同じ文法:
//   - サンバーストは Plotly 標準のドリルダウン(扇を押すとその部分を全体として展開)
//   - 右の「大分類」積み上げ棒を押すと、その大分類の中分類の積み上げ棒と
//     小分類の横棒(中分類ごと)を展開する
//   - 末端(小分類)の扇を押すと、そのジャンルで絞り込んだ語の一覧へ遷移する
// Plotly(vendor/javascript/plotly.min.js)はこのページ専用のため、接続時に1度だけ読み込む。
export default class extends Controller {
  static targets = ["data", "sunburst", "largeBar",
                    "mediumContainer", "mediumTitle", "mediumBar",
                    "smallContainer", "smallTitle", "smallBars"]
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

  // --- 大分類の積み上げ棒(押すとその大分類の内訳を展開) ---

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

  // --- 選んだ大分類の中分類(積み上げ棒)と小分類(横棒) ---

  expandLarge(largeId) {
    const large = this.nodeOf(largeId)
    const mediumIds = this.childrenOf(largeId)

    this.mediumContainerTarget.hidden = false
    this.mediumTitleTarget.textContent = large.label
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
        hovertemplate: this.hoverTemplate(node.label)
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
    if (!this.plots.includes(this.mediumBarTarget)) this.plots.push(this.mediumBarTarget)

    this.renderSmallBars(large, mediumIds)
  }

  renderSmallBars(large, mediumIds) {
    this.smallContainerTarget.hidden = false
    this.smallTitleTarget.textContent = `${large.label}${this.smallsSuffixValue}`
    this.smallBarsTarget.querySelectorAll("[data-plot]").forEach((element) => {
      window.Plotly.purge(element)
      this.plots = this.plots.filter((plot) => plot !== element)
    })
    this.smallBarsTarget.innerHTML = ""

    mediumIds.forEach((mediumId, mediumIndex) => {
      const medium = this.nodeOf(mediumId)
      const smallIds = this.childrenOf(mediumId)
      const container = document.createElement("div")
      container.className = "genre-analysis__small-bar"
      container.dataset.plot = "true"
      this.smallBarsTarget.appendChild(container)

      const traces = smallIds.map((id, index) => {
        const node = this.nodeOf(id)
        return {
          y: [ "" ],
          x: [ node.value ],
          name: node.label,
          type: "bar",
          orientation: "h",
          marker: {
            color: this.constructor.palette[(mediumIndex * 2 + index) % this.constructor.palette.length],
            line: { color: "#FAF8F3", width: 1.5 }
          },
          hovertemplate: this.hoverTemplate(node.label),
          text: [ node.label ],
          textposition: "inside",
          textfont: { size: 11 }
        }
      })

      window.Plotly.newPlot(container, traces, {
        ...this.baseLayout(),
        barmode: "stack",
        showlegend: false,
        margin: { l: 110, r: 8, t: 4, b: 4 },
        xaxis: { visible: false },
        yaxis: { visible: true, showticklabels: false, fixedrange: true },
        annotations: [ {
          x: 0, y: 0.5, xref: "paper", yref: "paper",
          text: medium.label, showarrow: false, xanchor: "right", xshift: -8,
          font: { size: 12 }
        } ]
      }, this.plotConfig())
      this.plots.push(container)
    })
  }
}
