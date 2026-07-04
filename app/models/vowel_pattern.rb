# 韻パターン(rhythm_pattern, ヘボン式ローマ字)から母音 aiueo のみを抜き出した文字列を
# 生成する値オブジェクト。母音一致での押韻検索・分類の軸に使う。
# 生成は Ruby 側で行い、WordSense の before_validation で(rhythm_pattern の後に)自動セットする。
#
# rhythm_pattern は長音を母音展開済み(とうきょう→toukyou / カレー→karee)のため、
# ここから母音だけを残せば母音パターン(toukyou→ouou / karee→aee)が得られる。
class VowelPattern
  NON_VOWEL = /[^aeiou]/

  # rhythm_pattern から母音のみを連結して返す。nil / 空文字は空文字。
  def self.call(rhythm_pattern)
    rhythm_pattern.to_s.gsub(NON_VOWEL, "")
  end
end
