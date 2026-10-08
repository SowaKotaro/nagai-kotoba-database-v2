// 注釈フォームの語義(.js-sense)についての判定。publish-guard(1語コンソール)と deck(10件デッキ)が
// 同じ数え方をするためにここだけで定める(sense-cloner も、複製の元を選ぶのに使う)。
// 「表示中」は、「この語義を削除」で隠されていない語義(sense-cloner が保存済みの語義の style.display を "none" にする)。

export function visibleSenses(root) {
  return [ ...root.querySelectorAll(".js-sense") ].filter((sense) => sense.style.display !== "none")
}

// 表示中の語義が 1 つ以上あり、すべて完了(sense-completeness が付ける is-complete)か。
export function allSensesComplete(root) {
  const senses = visibleSenses(root)
  return senses.length > 0 && senses.every((sense) => sense.classList.contains("is-complete"))
}
