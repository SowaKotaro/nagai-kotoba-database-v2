import { Controller } from "@hotwired/stimulus"

// 最低限のアノテーション項目(読み・語種・ジャンル・品詞・エンティティ)が
// すべて埋まった語義カードの枠を緑にする。未入力でも保存はできるので、これは
// 「最低限の注釈が付いた」ことを示す表示だけの指標。
export default class extends Controller {
  static targets = ["reading", "genre", "origins", "partOfSpeech", "entityType"]

  connect() {
    this.check()
  }

  check() {
    this.element.classList.toggle("is-complete", this.complete)
  }

  get complete() {
    // ジャンルの隠し値は小分類(末端)を選んだときだけ入る(genre-picker)。
    return this.filled(this.readingTarget.value) &&
      this.filled(this.genreTarget.value) &&
      this.anyChosen(this.originsTarget) &&
      this.anyChosen(this.partOfSpeechTarget) &&
      this.anyChosen(this.entityTypeTarget)
  }

  filled(value) {
    return value.trim() !== ""
  }

  // 「指定なし」ラジオは value が空なので、選択とはみなさない。
  // <template> の中の雛形は querySelectorAll では拾われないため除外は不要。
  anyChosen(container) {
    return [ ...container.querySelectorAll("input:checked") ].some((input) => this.filled(input.value))
  }
}
