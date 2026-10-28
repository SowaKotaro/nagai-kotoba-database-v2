import { Controller } from "@hotwired/stimulus"

// 探すための一覧(ジャンル /genres・エンティティ /entity_types)を、打った名前で絞り込む。
//   ジャンルは分類が 大 → 中 → 小 に畳まれていて、「アニメ」「鉄道」がどの大分類にあるかは開くまで分からない。
//   エンティティは語の多い順に並ぶので、探している名前(駅名 など)が後ろのほうに埋もれる。
// サーバがすべての項目を描き、欄(field)は JS がつながってから出す。JS が無いときは欄が無いだけで、一覧はそのまま辿れる。
// - item: 絞り込む単位。data-filter-terms の文字列に、打った文字が含まれれば残す
//   (ジャンルの小分類は中分類の名前も持つので、「漫画」と打てば 漫画・コミック の小分類がまとめて残る)
// - group: item を束ねる入れ物(ジャンルの中分類の束・大分類の折り畳み)。中に残った item が無ければ隠す。
//   折り畳み(details)は、絞り込んでいる間は開き、欄を空にしたら絞り込みで開いたものだけを閉じ直す
// - empty: 何も残らなかったときの一言
// ひらがなはカタカナへ、全角の英数は半角へ寄せ、大文字小文字も区別しない(「あにめ」でも「アニメ」に当たる)。
// 戻る操作(Turbo のスナップショット)で欄に文字が残っていたら、つながったときに同じ絞り込みを付け直す。
export default class extends Controller {
  static targets = ["field", "input", "item", "group", "empty"]

  connect() {
    this.fieldTarget.hidden = false
    if (this.inputTarget.value) this.filter()
  }

  filter() {
    const query = normalize(this.inputTarget.value.trim())

    this.itemTargets.forEach((item) => {
      item.hidden = query !== "" && !normalize(item.dataset.filterTerms).includes(query)
    })
    this.groupTargets.forEach((group) => {
      const visible = this.itemTargets.some((item) => !item.hidden && group.contains(item))
      group.hidden = !visible
      if (group instanceof HTMLDetailsElement) this.toggleFold(group, query !== "" && visible)
    })
    this.emptyTarget.hidden = query === "" || this.itemTargets.some((item) => !item.hidden)
  }

  // 人が開いた折り畳みは、欄を空にしても閉じない(閉じ直すのは絞り込みで開いたものだけ)。
  toggleFold(fold, open) {
    if (open && !fold.open) {
      fold.open = true
      fold.dataset.listFilterOpened = ""
    } else if (!open && "listFilterOpened" in fold.dataset) {
      fold.open = false
      delete fold.dataset.listFilterOpened
    }
  }
}

function normalize(text) {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[ぁ-ゖ]/g, (char) => String.fromCharCode(char.charCodeAt(0) + 0x60))
}
