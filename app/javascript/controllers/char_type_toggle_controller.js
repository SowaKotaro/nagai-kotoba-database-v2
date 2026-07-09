import { Controller } from "@hotwired/stimulus"

// VSCode の検索窓のような文字種の切替アイコン(Aa / "ab")。
// 押すたびに「厳密(完全一致 / 大文字小文字を区別する)」と
// 「緩い(部分一致 / 大文字小文字を区別しない)」を切り替える。
// hidden(input) には緩い側のとき "1"、厳密側のとき "" を入れる
// (サーバ側の char_type_partial / char_type_ignore_case と対応)。
// 点灯(aria-pressed=true)は「厳密側が有効」を表す。
// 切り替えた瞬間だけ、選んだ状態のラベルを 3 秒間フェード表示する(ホバー tooltip は使わない)。
export default class extends Controller {
  static targets = ["input", "button", "tip"]

  toggle() {
    const relaxed = this.inputTarget.value === "1"
    this.apply(!relaxed)
  }

  apply(relaxed) {
    this.inputTarget.value = relaxed ? "1" : ""
    const strict = !relaxed
    this.buttonTarget.setAttribute("aria-pressed", String(strict))
    const label = strict ? this.buttonTarget.dataset.titleStrict : this.buttonTarget.dataset.titleRelaxed
    this.buttonTarget.setAttribute("aria-label", label)
    this.showTip(label)
    // 切替に連動したい相手(大文字小文字トグル → 「a」キーの表示)へ知らせる。
    this.dispatch("changed", { detail: { strict } })
  }

  // 選択直後に状態ラベルを 3 秒だけ表示(フェードは CSS の transition が担う)。
  showTip(text) {
    if (!this.hasTipTarget) return

    this.tipTarget.textContent = text
    this.tipTarget.classList.add("is-visible")
    clearTimeout(this.hideTimer)
    this.hideTimer = setTimeout(() => this.tipTarget.classList.remove("is-visible"), 3000)
  }

  disconnect() {
    clearTimeout(this.hideTimer)
  }
}
