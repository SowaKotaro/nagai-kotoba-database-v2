import { Controller } from "@hotwired/stimulus"
import { normalizeSearchText } from "controllers/support/search_text"

// タグの統合(/admin/tags/:kind の「タグを統合する」)で、統合元と統合先を探しやすくする。
//   タグが増えて、すべてを並べたプルダウンから 2 つを探すのが大変になったため。
// - 統合元・統合先それぞれに名前で絞り込む欄(sourceQuery / targetQuery)を出し、選択肢(sourceSelect / targetSelect)を
//   一覧(size 付きの select)にして、打つたびに当たる選択肢だけを並べ直す。空白で区切ると、すべての語を含むものに絞る
//   (ジャンルは「大 › 中 › 小」の名前で当てるので、中分類の名前を打てば配下の小分類がまとめて残る)。
// - 統合先は、統合元と同じ階層(data-level。ジャンルだけが持つ)のものだけを並べ、統合元そのものは外す
//   (サーバの Genre#merge_into! が受け付けない組み合わせを最初から選ばせない)。
// - 当たるものが無いときは、選べない一言(data-tag-merge-empty-value)を 1 行出す。
// JS が無いときは、欄は出ず(hidden で描く)、ふつうのプルダウンのまま全件から選べる。
// select は並べ直すたびに作り直すので、元の選択肢はつながったときに控えておく。選んでいた値は、残っていれば保つ。
// Turbo がページを控える前(turbo:before-cache@document->tag-merge#reset)に全件へ戻す。絞ったまま控えられると、
// 戻ったときにつながり直したこのコントローラが、絞られた選択肢を元の全件として控えてしまう。
export default class extends Controller {
  static targets = ["sourceQuery", "sourceSelect", "targetQuery", "targetSelect", "field"]
  static values = { empty: String, size: { type: Number, default: 8 } }

  connect() {
    this.sourceOptions = this.snapshot(this.sourceSelectTarget)
    this.targetOptions = this.snapshot(this.targetSelectTarget)
    this.fieldTargets.forEach((field) => (field.hidden = false))
    this.sourceSelectTarget.size = this.sizeValue
    this.targetSelectTarget.size = this.sizeValue
    this.filterSource()
  }

  reset() {
    this.sourceQueryTarget.value = ""
    this.targetQueryTarget.value = ""
    this.restore(this.sourceSelectTarget, this.sourceOptions)
    this.restore(this.targetSelectTarget, this.targetOptions)
  }

  filterSource() {
    this.render(this.sourceSelectTarget, this.sourceOptions, this.sourceQueryTarget.value, () => true)
    this.filterTarget()
  }

  filterTarget() {
    const source = this.sourceOptions.find((option) => option.value === this.sourceSelectTarget.value)
    this.render(this.targetSelectTarget, this.targetOptions, this.targetQueryTarget.value, (option) =>
      !source || (option.value !== source.value && option.level === source.level))
  }

  // 選択肢を { value, label, level, search } の配列に控える(空の「選択してください」は除き、その文言は別に控える)。
  snapshot(select) {
    select.dataset.blankLabel = select.options[0]?.value === "" ? select.options[0].textContent : ""
    return Array.from(select.options)
      .filter((option) => option.value !== "")
      .map((option) => ({
        value: option.value,
        label: option.textContent,
        level: option.dataset.level || "",
        search: normalizeSearchText(option.textContent)
      }))
  }

  // JS が無いときと同じ、空の行つきのプルダウン(全件)に戻す。
  restore(select, options) {
    select.size = 0
    select.replaceChildren(new Option(select.dataset.blankLabel, ""), ...options.map((option) => this.build(option)))
  }

  build(option) {
    const element = new Option(option.label, option.value)
    if (option.level) element.dataset.level = option.level
    return element
  }

  render(select, options, query, allowed) {
    const words = normalizeSearchText(query.trim()).split(/\s+/).filter(Boolean)
    const matches = options.filter((option) => allowed(option) && words.every((word) => option.search.includes(word)))
    const selected = select.value

    select.replaceChildren(...matches.map((option) => this.build(option)))
    if (matches.length === 0) {
      const empty = new Option(this.emptyValue, "")
      empty.disabled = true
      select.append(empty)
    }
    select.value = matches.some((option) => option.value === selected) ? selected : ""
  }
}
