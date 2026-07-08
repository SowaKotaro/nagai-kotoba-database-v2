# 表層形(surface)を1文字ずつ「文字種」に写像した文字列を生成する値オブジェクト。
#   漢字        → 漢
#   ひらがな    → あ
#   カタカナ    → ア（半角カタカナ・長音符も含む）
#   数字        → 1（全角・半角を区別しない）
#   英大文字    → A（全角・半角を区別しない）
#   英小文字    → a（全角・半角を区別しない）
#   それ以外    → @（記号・空白・その他）
# 例: "ABC殺人事件" → "AAA漢漢漢漢" / "Web3.0" → "Aaa1@1"
# 大文字小文字は区別する(A/a)が、全角/半角は区別しない(数字・英字とも1文字種に畳む)。
# 変換仕様の詳細は docs/char_type_pattern.md を参照。
class CharTypePattern
  KANJI    = "漢"
  HIRAGANA = "あ"
  KATAKANA = "ア"
  DIGIT    = "1"
  UPPER    = "A"
  LOWER    = "a"
  OTHER    = "@"

  # 文字種判定の順序は重要。上から順に最初に一致したものを採用する。
  # 長音符 ー(U+30FC)・半角長音符 ｰ(U+FF70) は Unicode 上カタカナに分類されないが、
  # カタカナ語の伸ばす音として頻出するためカタカナ(ア)として扱う。
  # 数字・英字は全角/半角を同じ文字種に畳むため、全角(０-９/Ａ-Ｚ/ａ-ｚ)も含めて判定する。
  RULES = [
    [ /\p{Han}/,                          KANJI ],
    [ /\p{Hiragana}/,                     HIRAGANA ],
    [ /[\p{Katakana}\u{30FC}\u{FF70}]/,   KATAKANA ],
    [ /[0-9０-９]/,                       DIGIT ],
    [ /[A-ZＡ-Ｚ]/,                       UPPER ],
    [ /[a-zａ-ｚ]/,                       LOWER ]
  ].freeze

  # surface から char_type_pattern 文字列を生成する。
  # nil は空文字として扱う。
  def self.call(text)
    text.to_s.each_char.map { |char| classify(char) }.join
  end

  def self.classify(char)
    RULES.each { |pattern, symbol| return symbol if char.match?(pattern) }
    OTHER
  end
  private_class_method :classify
end
