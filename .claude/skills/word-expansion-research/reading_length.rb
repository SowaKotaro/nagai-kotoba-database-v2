# /expand の候補を「読み10文字以上」で厳密にふるうための補助スクリプト。
#
# 使い方（リポジトリのルートで）:
#   bin/rails runner .claude/skills/word-expansion-research/reading_length.rb < pairs.tsv
#
# 入力: 1行1語「表層形<TAB>読み(カタカナ)」。読みはスキル側で決めたもの（guidelines §4 の表記ルール）。
# 出力: 「判定<TAB>表層形<TAB>読み<TAB>文字数<TAB>MeCabの読み<TAB>MeCabの文字数」（TSV）。
#   判定: OK（10文字以上）／短い（10文字未満）／要確認（MeCab と数え方が 10文字の境界をまたぐ）／読みなし
#
# 判定の規則はアプリの ReadingLengthCheck が持つ（調査の自動実行と同じ判定）。ここで独自に数え方を定義しない。
# mecab が無い環境でも止めない（MeCab 欄が空になり、判定はスキルの読みだけで行う）。

LABELS = { ok: "OK", short: "短い", uncertain: "要確認", missing: "読みなし" }.freeze

rows = $stdin.each_line.map(&:chomp).reject(&:blank?).map { |line| line.split("\t", 2) }
mecab_readings = ReadingExtractor.call(rows.map(&:first))

rows.each_with_index do |(surface, reading), index|
  check = ReadingLengthCheck.call(reading, mecab_readings[index])
  puts [ LABELS.fetch(check.verdict), surface, check.reading, check.length, check.mecab_reading, check.mecab_length ].join("\t")
end
