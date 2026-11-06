import { Controller } from "@hotwired/stimulus"

// 900px 以下のヘッダーのドロワー(docs/design.md §5.1)。ハンバーガーで、ナビ(「検索」の折り畳みとテーマの
// 切り替えを含む)を収めた右からのパネルを開閉する。広い幅ではパネルがヘッダーの右側にそのまま並ぶので、ここは働かない。
// 開閉の見た目(三本線が × になる・パネルが滑る・スクリムが薄れる・行が順に出る)はすべて CSS が、このコントローラが付け外す
// クラスと aria-expanded から描く。行が順に出るのだけは、開くたびに行の数が変わる(畳んだ「検索」の中の行が見えているか、
// ログイン中か)ので、見えている行に上から順に番号(--row)を振り、開いた直後の間だけ is-entering を付ける。
// ハンバーガーは開くとドロワーの手前で × になり、そのまま閉じるボタンを兼ねる
// (閉じるボタンを別に持たないので、フォーカスは開いても動かさない。閉じるときだけ、パネルの中にあったフォーカスをハンバーガーへ戻す)。
// 閉じるのは、ハンバーガー・スクリムのクリック・Escape・Turbo のキャッシュの直前(開いたまま残すと、戻ったときに開いて見える)。
// Escape とキャッシュは shared/_header の data-action で受ける。開閉は nav-drawer:open / nav-drawer:close で知らせる
// (header-reveal が、開いている間ヘッダーを出したままにするのに使う)。
// JS が無いとハンバーガーが効かず、狭幅ではナビに届かない(docs/design.md §6)。閉じたパネルは CSS が visibility でも隠すので、Tab で入らない。
export default class extends Controller {
  static targets = ["panel", "scrim", "button"]
  static values = { openLabel: String, closeLabel: String }

  // 順に出す行。ナビの行・「検索」とその中の行・ログアウト・テーマの切り替え(layout.css の .is-entering と同じ並び)
  static rowSelector = ".site-nav > a, .nav-menu__trigger, .nav-menu__panel a, .site-nav form button, .theme-toggle__button"
  // 行が出終わるまでの目安(ms)。出る間の印(is-entering)を外す。CSS の遅れ(120ms + 45ms × 行数。12 行で約 660ms)と出る時間(380ms)に足りる長さ
  static enteringDuration = 1400

  disconnect() {
    clearTimeout(this.enteringTimer)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.panelTarget.classList.add("is-open")
    this.scrimTarget.classList.add("is-open")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.buttonTarget.setAttribute("aria-label", this.closeLabelValue)
    document.body.classList.add("nav-drawer-open")
    this.enter()
    this.dispatch("open")
  }

  // 見えている行に、上から順に番号を振って(畳んだ「検索」の中の行は数えない)、開いた直後の間だけ印を付ける。
  // 「検索」を自分で開閉したとき(中の行が display: none から現れる)に、行の動きが走らないよう、印は開いた直後の間だけにする
  enter() {
    const rows = [...this.panelTarget.querySelectorAll(this.constructor.rowSelector)]
      .filter((row) => row.getClientRects().length > 0)
    rows.forEach((row, index) => row.style.setProperty("--row", index))
    this.panelTarget.classList.add("is-entering")
    clearTimeout(this.enteringTimer)
    this.enteringTimer = setTimeout(() => this.panelTarget.classList.remove("is-entering"), this.constructor.enteringDuration)
  }

  // Escape は開いていなくても届く(ホームの選択肢のシートなど、ほかの部品を閉じる Escape)ので、閉じているときは何もしない
  close() {
    if (!this.isOpen) return

    const focusWasInside = this.panelTarget.contains(document.activeElement)
    clearTimeout(this.enteringTimer)
    this.panelTarget.classList.remove("is-open", "is-entering")
    this.scrimTarget.classList.remove("is-open")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.setAttribute("aria-label", this.openLabelValue)
    document.body.classList.remove("nav-drawer-open")
    if (focusWasInside) this.buttonTarget.focus()
    this.dispatch("close")
  }

  get isOpen() {
    return this.panelTarget.classList.contains("is-open")
  }
}
