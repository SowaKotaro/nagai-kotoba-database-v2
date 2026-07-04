import { Controller } from "@hotwired/stimulus"

// 「語義を追加」: 直前の語義を複製し、語種・品詞・特徴(の種別と単語側の該当部分)を
// 引き継ぎつつ、読み・意味・ジャンル・エンティティ・別表記・特徴の読み側は空にした
// 新しい語義を下に追加する(同音異義語の入力を素早くするため)。
// ネスト属性の添字は新しい一意値へ置換し、id/_destroy を外して新規レコード扱いにする。
export default class extends Controller {
  static targets = ["container"]

  add(event) {
    event.preventDefault()
    const senses = this.containerTarget.querySelectorAll(".js-sense")
    const last = senses[senses.length - 1]
    if (!last) return

    const oldIndex = last.dataset.index
    const newIndex = Date.now().toString()
    const prefix = "[word_senses_attributes]["
    const html = last.outerHTML.split(prefix + oldIndex + "]").join(prefix + newIndex + "]")

    const holder = document.createElement("div")
    holder.innerHTML = html
    const clone = holder.firstElementChild
    clone.dataset.index = newIndex
    clone.style.display = ""

    // 新規レコード扱い: 既存 id を除去、_destroy(語義・特徴・別表記)を初期化。
    clone.querySelectorAll('input[name$="[id]"]').forEach((el) => el.remove())
    clone.querySelectorAll("input[data-nested-form-destroy], input[data-sense-destroy]")
      .forEach((el) => (el.value = ""))

    // クリアする項目: 読み・意味。
    clone.querySelectorAll(".js-reading, .js-meaning").forEach((el) => (el.value = ""))
    // エンティティは「指定なし」へ。
    const none = clone.querySelector(".js-entity-none")
    if (none) none.checked = true
    // 別表記は空に。
    const variants = clone.querySelector(".js-variants")
    if (variants) variants.innerHTML = ""
    // ジャンルはリセット(現在パス行を消し、隠し値を空に)。表示は picker の connect が整える。
    const genreValue = clone.querySelector(".js-genre-value")
    if (genreValue) genreValue.value = ""
    const genreCurrent = clone.querySelector(".js-genre-current")
    if (genreCurrent) genreCurrent.remove()
    // 特徴は種別と「単語側の該当部分」を引き継ぎ、読み側の該当部分は空にする(読みが変わるため)。
    clone.querySelectorAll('input[name$="[target_reading]"]').forEach((el) => (el.value = ""))

    this.containerTarget.appendChild(clone)
    clone.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  // 「この語義を削除」: 永続化済みは _destroy を立てて隠す。新規行は DOM から除去。
  remove(event) {
    event.preventDefault()
    const item = event.target.closest(".js-sense")
    if (!item) return
    const destroy = item.querySelector("input[data-sense-destroy]")
    const persisted = item.querySelector('input[name$="[id]"]')
    if (destroy && persisted) {
      destroy.value = "1"
      item.style.display = "none"
    } else {
      item.remove()
    }
  }
}
