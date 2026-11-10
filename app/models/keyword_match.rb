# キーワード検索(WordSense::KEYWORD_MATCH_CONDITION の LIKE)が、文字列のどこに当たったかを Ruby で求める値オブジェクト。
# 検索結果のハイライト(SearchHighlight)と、「別表記だけが一致した」注記の判定が使う。
#
# LIKE は表層形・読みの照合順序 utf8mb4_0900_as_ci で比べるので、次を同じ字とみなす(MySQL 8.4 で実測)。
#   - ひらがなとカタカナ(しょう = ショウ)
#   - 小書きと並字(ショ = シヨ。ヵ・ヶ も カ・ケ と同じ)
#   - 全角と半角(ｶﾀ = カタ、ＡＢＣ = ABC)と、欧字の大文字小文字
# 清濁は区別する(ハ ≠ バ。docs/data-model.md §6)。ここでは 1 字ずつ畳み、畳む前と後で字の位置が変わらないようにする
# (位置がずれると、ハイライトする範囲がずれる)。1 字が 2 字以上に開く字(㌔ など)は畳まずに残す。
# 畳み方が DB と食い違っても、ハイライトや注記がずれるだけで、検索の結果は変わらない。
# 種別: 値オブジェクト（DB に触れない）。
class KeywordMatch
  SMALL_KANA = "ァィゥェォッャュョヮヵヶ".freeze
  LARGE_KANA = "アイウエオツヤユヨワカケ".freeze

  # text の中でキーワード query に当たる範囲(文字の位置の Range)を、重なりをまとめて先頭から順に返す。
  # query が空なら空配列。
  def self.ranges(text, query)
    needle = fold(query.to_s.strip.unicode_normalize(:nfkc))
    return [] if needle.empty?

    haystack = fold(text.to_s)
    found = []
    start = haystack.index(needle)
    while start
      found << (start...(start + needle.length))
      start = haystack.index(needle, start + 1)
    end
    merge(found)
  end

  # 範囲の並びを先頭順に並べ、重なる・接する範囲を 1 つにまとめる。
  def self.merge(ranges)
    ranges.sort_by(&:begin).each_with_object([]) do |range, merged|
      if merged.any? && range.begin <= merged.last.end
        merged[-1] = (merged.last.begin...[ merged.last.end, range.end ].max)
      else
        merged << range
      end
    end
  end

  # 1 字ずつ畳む(字数は変えない)。
  def self.fold(text)
    text.each_char.map { |char| fold_char(char) }.join
  end

  def self.fold_char(char)
    folded = KanaFold.to_katakana(char).tr(SMALL_KANA, LARGE_KANA).downcase
    folded.length == 1 ? folded : char
  end

  private_class_method :fold, :fold_char
end
