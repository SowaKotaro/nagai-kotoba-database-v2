import { Controller } from "@hotwired/stimulus"

// 検索の絞り込み用ジャンル階層(ドロップダウンを使わない)。
//   チップはチェックボックス(genre_id[])で、複数の節点を同時に選べる。
//   初期状態は大分類のみを表示し、親をチェックすると直下の子グループが
//   フェードイン(CSS)で現れる。複数の親を選べば複数のグループが並ぶ。
//   親のチェックを外すと、配下(子・孫)のチェックと表示もまとめて解除する。
//   上位と下位を同時に選んだ場合の優先はサーバ側(WordSenseSearch)が扱う。
export default class extends Controller {
  static targets = ["box", "group"]

  connect() {
    this.sync()
  }

  toggle(event) {
    const box = event.target
    if (!box.checked) this.uncheckDescendants(box.value)
    this.sync()
  }

  // 指定した親の配下(子・孫)のチェックを再帰的に外す。
  uncheckDescendants(parentId) {
    this.boxTargets.forEach((box) => {
      if (box.dataset.parent === parentId && box.checked) {
        box.checked = false
        this.uncheckDescendants(box.value)
      }
    })
  }

  // チェック済みの節点を親に持つ子グループだけを表示する。
  sync() {
    const checkedIds = this.boxTargets.filter((box) => box.checked).map((box) => box.value)
    this.groupTargets.forEach((group) => {
      group.hidden = !checkedIds.includes(group.dataset.parent)
    })
  }
}
