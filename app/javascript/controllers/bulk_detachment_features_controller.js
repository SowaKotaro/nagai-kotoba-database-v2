import { Controller } from "@hotwired/stimulus"

// 単語の修正の一覧の「まとめて外す」(Issue 108)で、言語学的特徴の選択肢を、選択した語すべてに付いている特徴だけに絞る
// (admin/words/_bulk_detachment)。付いていない語を含めて外すと、一部の語からだけ外れて、選んだ範囲と結果が食い違うため。
// - 行のチェックボックスはフォームの外にあり、form 属性で一括フォームに紐づくので、フォームの elements から
//   data-feature-ids(その語の語義に付いた特徴の id。空白区切り)を持つものを読み、チェックした語の共通部分を求める
// - 共通部分に無い特徴のチップは隠す。選んであったチップが隠れるときは「外さない」に戻す(隠れたまま送られないように)
// - 1 語も選んでいないうちは全部を出す。一覧の特徴の絞り込みで選ばれた初期値を、全選択するまで残すため
// JS が無いと全部の特徴が出たままになり、付いていない語を含む送信はサーバ(BulkDetachment)がエラーで止める。
// 行のチェック・全選択の変更は change@document で受ける(全選択のヘッダも、本物の change が document まで届く)。
export default class extends Controller {
  static targets = ["chip", "keep", "status"]
  static values = { hint: String, noneSelected: String, noneShared: String }

  connect() {
    this.refresh()
  }

  refresh() {
    const selected = this.selectedBoxes()
    const shared = this.sharedFeatureIds(selected)

    this.chipTargets.forEach((chip) => {
      const available = selected.length === 0 || shared.has(chip.dataset.recordId)
      const input = chip.querySelector("input")
      if (!available && input.checked) this.keepTarget.querySelector("input").checked = true
      chip.hidden = !available
    })

    this.statusTarget.hidden = false
    if (selected.length === 0) {
      this.statusTarget.textContent = this.noneSelectedValue
    } else if (shared.size === 0) {
      this.statusTarget.textContent = this.noneSharedValue
    } else {
      this.statusTarget.textContent = this.hintValue
    }
  }

  selectedBoxes() {
    const form = this.element.closest("form")
    if (!form) return []

    return Array.from(form.elements).filter((input) => "featureIds" in input.dataset && input.checked)
  }

  // 選択した語すべてに共通する特徴の id。
  sharedFeatureIds(boxes) {
    if (boxes.length === 0) return new Set()

    const [first, ...rest] = boxes.map((box) => new Set((box.dataset.featureIds || "").split(" ").filter(Boolean)))
    return new Set([...first].filter((id) => rest.every((ids) => ids.has(id))))
  }
}
