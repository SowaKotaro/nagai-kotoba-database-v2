// 打った文字と名前を突き合わせる前に、表記の揺れを寄せる(名前で絞り込む欄が共有する)。
// ひらがなはカタカナへ、全角の英数は半角へ寄せ、大文字小文字も区別しない(「あにめ」でも「アニメ」に当たる)。
export function normalizeSearchText(text) {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[ぁ-ゖ]/g, (char) => String.fromCharCode(char.charCodeAt(0) + 0x60))
}
