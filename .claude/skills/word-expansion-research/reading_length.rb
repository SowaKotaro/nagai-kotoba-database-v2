# /expand の候補を「読み10文字以上」で厳密にふるうための補助スクリプト。
#
# 使い方（リポジトリのルートで）:
#   bin/rails runner .claude/skills/word-expansion-research/reading_length.rb < pairs.tsv
#
# 入力: 1行1語「表層形<TAB>読み(カタカナ)」。読みはスキル側で決めたもの（guidelines §4 の表記ルール）。
# 出力: 「判定<TAB>表層形<TAB>読み<TAB>文字数<TAB>MeCabの読み<TAB>MeCabの文字数」（TSV）。
#   判定: OK（10文字以上）／短い（10文字未満）／要確認（MeCab と数え方が 10文字の境界をまたぐ）／読みなし
#
# 数え方はアプリと同じにする: 読みの正規化は ReadingExtractor（カタカナと長音符だけを残す）、
# 文字数は word_senses.reading_length（char_length）と同じく1文字ずつ数え、基準値は
# WordSense::MIN_READING_LENGTH を使う。ここで独自に数え方を定義しない。
# mecab が無い環境でも止めない（MeCab 欄が空になり、判定はスキルの読みだけで行う）。

min_length = WordSense::MIN_READING_LENGTH
extractor = ReadingExtractor.new
# 正規化の規則は ReadingExtractor#normalize が持つ。ここで定義を複製しない。
normalize = ->(reading) { extractor.normalize(reading) }

rows = $stdin.each_line.map(&:chomp).reject(&:blank?).map { |line| line.split("\t", 2) }
mecab_readings = ReadingExtractor.call(rows.map(&:first))

rows.each_with_index do |(surface, reading), index|
  own = normalize.call(reading)
  mecab = mecab_readings[index]
  own_length = own&.length
  mecab_length = mecab&.length

  verdict =
    if own.nil? then "読みなし"
    elsif mecab_length && (own_length >= min_length) != (mecab_length >= min_length) then "要確認"
    elsif own_length >= min_length then "OK"
    else "短い"
    end

  puts [ verdict, surface, own, own_length, mecab, mecab_length ].join("\t")
end
