import { Controller } from "@hotwired/stimulus"

// ダークモードの切り替え(docs/design.md §9)。
// 既定は OS 設定に追従し、トグルを押したときだけ html[data-theme] で上書きして
// localStorage に覚える。初回描画のちらつきを防ぐ復元は layouts/application.html.erb
// の head 内インラインスクリプトが担当していて、ここは操作と表示の同期だけを行う。
const STORAGE_KEY = "theme"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.systemDark = window.matchMedia("(prefers-color-scheme: dark)")
    // 手動で上書きしていないときだけ、OS 側の切り替えにスイッチの見た目を追従させる
    this.systemChanged = () => this.sync()
    this.systemDark.addEventListener("change", this.systemChanged)
    this.sync()
  }

  disconnect() {
    this.systemDark.removeEventListener("change", this.systemChanged)
  }

  toggle() {
    document.documentElement.dataset.theme = this.dark ? "light" : "dark"
    this.save(document.documentElement.dataset.theme)
    this.sync()
  }

  // 現在ダークかどうか。手動の上書きがあればそれが勝ち、無ければ OS 設定に従う
  get dark() {
    const theme = document.documentElement.dataset.theme
    if (theme === "dark" || theme === "light") return theme === "dark"
    return this.systemDark.matches
  }

  sync() {
    this.buttonTarget.setAttribute("aria-checked", String(this.dark))
    // モバイルのブラウザ UI(アドレスバー)の色。値は CSS のトークンを正とする
    const themeColor = document.querySelector('meta[name="theme-color"]')
    if (themeColor) {
      themeColor.content = getComputedStyle(document.documentElement).getPropertyValue("--bg").trim()
    }
    // CSS だけでは追従できない描画(Plotly のグラフなど)に切り替えを知らせる
    document.dispatchEvent(new CustomEvent("theme:change", { detail: { dark: this.dark } }))
  }

  // プライベートブラウジング等で localStorage が使えなくても操作自体は通す
  save(theme) {
    try {
      window.localStorage.setItem(STORAGE_KEY, theme)
    } catch (error) {
      // 保存できないときはそのページの間だけ有効
    }
  }
}
