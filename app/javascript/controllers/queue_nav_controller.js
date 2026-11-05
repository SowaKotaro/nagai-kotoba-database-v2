import { Controller } from "@hotwired/stimulus"

// キュー操作のキーボードショートカット(任意・補助)。
//   Enter=保存して次へ / →=スキップ / ←=戻る。
// テキスト入力中は無効化して、通常の入力を邪魔しない(タップ操作が主・キーは補助)。
// もう 1 つの役目として、接続のたびに見出しが見える位置へスクロールする(scrollToHeading)。
//   広い画面ではページ先頭。縦に積む幅(annotate.css が .ann に --queue-nav-scroll: heading を立てる)では
//   見出し語(heading target)を画面の上端に合わせ、語ごとには要らないヘッダー・管理ナビ・残り件数・絞り込みを
//   画面の上へ出す(上へスクロールすれば見える)。
//   スマホでも「提案を全部読む → 保存して次へ」を 1 画面で済ませるため(docs/design.md §10.1.2)。
// JS が無いと: キー操作が効かず、スマホでは開くたびにページ先頭(ヘッダーの下に提案)から始まる。
export default class extends Controller {
  static targets = ["form", "skip", "back", "heading"]

  connect() {
    this.handler = this.onKey.bind(this)
    document.addEventListener("keydown", this.handler)
    // 「保存して次へ」で Turbo Frame の中身だけ差し替わると、その場で画面が変わり
    // 遷移したか分かりにくい。見出し(NO.・見出し語)が見える位置まで戻す。
    this.scrollToHeading()
  }

  scrollToHeading() {
    const mode = getComputedStyle(this.element).getPropertyValue("--queue-nav-scroll").trim()
    if (mode === "heading" && this.hasHeadingTarget) {
      // 上の余白は scroll-margin-top(annotate.css)が持つ
      this.headingTarget.scrollIntoView({ block: "start", behavior: "auto" })
    } else {
      window.scrollTo({ top: 0, left: 0, behavior: "auto" })
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.handler)
  }

  onKey(event) {
    const tag = (event.target.tagName || "").toLowerCase()
    if (tag === "input" || tag === "textarea") return

    if (event.key === "Enter") {
      event.preventDefault()
      this.formTarget.requestSubmit()
    } else if (event.key === "ArrowRight" && this.hasSkipTarget) {
      event.preventDefault()
      this.skipTarget.click()
    } else if (event.key === "ArrowLeft" && this.hasBackTarget) {
      event.preventDefault()
      this.backTarget.click()
    }
  }
}
