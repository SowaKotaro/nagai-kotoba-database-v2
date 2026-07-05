import { Controller } from "@hotwired/stimulus"

// 検索の絞り込み用ジャンル階層(ドロップダウンを使わない)。
//   大→中→小のチップはサーバ側で描画済み。中/小のグループは最初は隠しておき、
//   親を選ぶとその子グループだけを表示する(アノテーションと同じ体験)。
//   選んだ節点(どの階層でも可)の id を隠しフィールド genre_id に書き込む。
//   もう一度同じチップを押すと選択解除(下位の選択も解除)。
export default class extends Controller {
  static targets = ["value", "chip", "group"]

  select(event) {
    const chip = event.currentTarget
    const level = chip.dataset.level
    const child = nextLevel(level)

    // 選択解除(同じチップを再度押した)。
    if (chip.getAttribute("aria-pressed") === "true") {
      chip.setAttribute("aria-pressed", "false")
      this.valueTarget.value = ""
      if (child) this.clearFrom(child)
      return
    }

    // 同じ階層の他チップを解除し、この節点を選択。
    this.deactivateLevel(level)
    chip.setAttribute("aria-pressed", "true")
    this.valueTarget.value = chip.dataset.genreId

    // 下位はいったん解除し、この節点直下の子グループだけを表示する。
    if (child) {
      this.clearFrom(child)
      this.showGroupFor(chip.dataset.genreId)
    }
  }

  // 指定した親 id を持つ子グループだけを表示する。
  showGroupFor(parentId) {
    this.groupTargets.forEach((group) => {
      group.hidden = group.dataset.parent !== parentId
    })
  }

  // 指定階層以下(中/小)の選択と表示をリセットする。
  clearFrom(level) {
    const levels = level === "medium" ? ["medium", "small"] : ["small"]
    levels.forEach((lv) => {
      this.deactivateLevel(lv)
      this.groupTargets.forEach((group) => {
        if (group.dataset.level === lv) group.hidden = true
      })
    })
  }

  deactivateLevel(level) {
    this.chipTargets.forEach((chip) => {
      if (chip.dataset.level === level) chip.setAttribute("aria-pressed", "false")
    })
  }
}

function nextLevel(level) {
  if (level === "large") return "medium"
  if (level === "medium") return "small"
  return null
}
