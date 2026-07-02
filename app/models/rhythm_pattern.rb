# 読み(reading, かな)をヘボン式ローマ字へ変換した文字列を生成する値オブジェクト。
# 韻(リズム)での検索・分類の軸に使う。生成は Ruby 側で行い、
# WordSense の before_validation で自動セットする(手入力させない)。
#
# 方針(詳細は docs/rhythm_pattern.md):
#   - ヘボン式(し→shi, ち→chi, つ→tsu, ふ→fu, じ→ji, しゃ→sha)。
#   - 長音は母音をそのまま展開(とうきょう→toukyou)。長音符 ー は直前の母音を繰り返す(カレー→karee)。
#   - 促音 っ は次の子音を重ねる(がっこう→gakkou)。ただし ch の前は t(まっちゃ→matcha)。
#   - 撥音 ん は常に n(しんぶん→shinbun)。b/p/m の前でも m にしない(規則性優先の割り切り)。
class RhythmPattern
  SOKUON = "っ"  # 促音
  CHOUON = "ー"  # 長音符(NFKC・カタカナ→ひらがな変換後も残る)

  # ひらがな→ヘボン式ローマ字。拗音・外来音(2文字)を直音(1文字)より先に照合する。
  TABLE = {
    # --- 拗音・外来音(2文字) ---
    "きゃ" => "kya", "きゅ" => "kyu", "きょ" => "kyo",
    "しゃ" => "sha", "しゅ" => "shu", "しょ" => "sho", "しぇ" => "she",
    "ちゃ" => "cha", "ちゅ" => "chu", "ちょ" => "cho", "ちぇ" => "che",
    "にゃ" => "nya", "にゅ" => "nyu", "にょ" => "nyo",
    "ひゃ" => "hya", "ひゅ" => "hyu", "ひょ" => "hyo",
    "みゃ" => "mya", "みゅ" => "myu", "みょ" => "myo",
    "りゃ" => "rya", "りゅ" => "ryu", "りょ" => "ryo",
    "ぎゃ" => "gya", "ぎゅ" => "gyu", "ぎょ" => "gyo",
    "じゃ" => "ja",  "じゅ" => "ju",  "じょ" => "jo",  "じぇ" => "je",
    "ぢゃ" => "ja",  "ぢゅ" => "ju",  "ぢょ" => "jo",
    "びゃ" => "bya", "びゅ" => "byu", "びょ" => "byo",
    "ぴゃ" => "pya", "ぴゅ" => "pyu", "ぴょ" => "pyo",
    "ふぁ" => "fa",  "ふぃ" => "fi",  "ふぇ" => "fe",  "ふぉ" => "fo", "ふゅ" => "fyu",
    "てぃ" => "ti",  "でぃ" => "di",  "とぅ" => "tu",  "どぅ" => "du",
    "うぃ" => "wi",  "うぇ" => "we",  "うぉ" => "wo",
    "つぁ" => "tsa", "つぃ" => "tsi", "つぇ" => "tse", "つぉ" => "tso",
    "ゔぁ" => "va",  "ゔぃ" => "vi",  "ゔぇ" => "ve",  "ゔぉ" => "vo",
    "いぇ" => "ye",
    # --- 直音(1文字) ---
    "あ" => "a",  "い" => "i",  "う" => "u",  "え" => "e",  "お" => "o",
    "か" => "ka", "き" => "ki", "く" => "ku", "け" => "ke", "こ" => "ko",
    "が" => "ga", "ぎ" => "gi", "ぐ" => "gu", "げ" => "ge", "ご" => "go",
    "さ" => "sa", "し" => "shi", "す" => "su", "せ" => "se", "そ" => "so",
    "ざ" => "za", "じ" => "ji", "ず" => "zu", "ぜ" => "ze", "ぞ" => "zo",
    "た" => "ta", "ち" => "chi", "つ" => "tsu", "て" => "te", "と" => "to",
    "だ" => "da", "ぢ" => "ji", "づ" => "zu", "で" => "de", "ど" => "do",
    "な" => "na", "に" => "ni", "ぬ" => "nu", "ね" => "ne", "の" => "no",
    "は" => "ha", "ひ" => "hi", "ふ" => "fu", "へ" => "he", "ほ" => "ho",
    "ば" => "ba", "び" => "bi", "ぶ" => "bu", "べ" => "be", "ぼ" => "bo",
    "ぱ" => "pa", "ぴ" => "pi", "ぷ" => "pu", "ぺ" => "pe", "ぽ" => "po",
    "ま" => "ma", "み" => "mi", "む" => "mu", "め" => "me", "も" => "mo",
    "や" => "ya", "ゆ" => "yu", "よ" => "yo",
    "ら" => "ra", "り" => "ri", "る" => "ru", "れ" => "re", "ろ" => "ro",
    "わ" => "wa", "ゐ" => "i", "ゑ" => "e", "を" => "o", "ん" => "n",
    "ゔ" => "vu",
    # --- 小書き(単独で出現した場合) ---
    "ぁ" => "a", "ぃ" => "i", "ぅ" => "u", "ぇ" => "e", "ぉ" => "o",
    "ゃ" => "ya", "ゅ" => "yu", "ょ" => "yo", "ゎ" => "wa"
  }.freeze

  VOWELS = %w[a i u e o].freeze
  # 促音で重ねる対象となる子音で始まるか。母音始まりには促音を適用しない。
  CONSONANT_HEAD = /\A[bcdfghjklmnpqrstvwyz]/

  # reading から rhythm_pattern 文字列を生成する。nil は空文字として扱う。
  def self.call(reading)
    chars = normalize(reading).chars
    result = +""
    pending_sokuon = false
    index = 0

    while index < chars.length
      char = chars[index]

      if char == CHOUON
        # 長音符は直前の母音を繰り返す(母音が無ければ無視)。
        result << last_vowel(result).to_s
        index += 1
        next
      end

      if char == SOKUON
        pending_sokuon = true
        index += 1
        next
      end

      pair = chars[index, 2].join
      if chars[index + 1] && TABLE.key?(pair)
        romaji = TABLE[pair]
        index += 2
      elsif TABLE.key?(char)
        romaji = TABLE[char]
        index += 1
      else
        # 変換表に無い文字(記号など)はそのまま通す。促音フラグは持ち越さない。
        result << char
        pending_sokuon = false
        index += 1
        next
      end

      if pending_sokuon
        romaji = apply_sokuon(romaji)
        pending_sokuon = false
      end
      result << romaji
    end

    result
  end

  # NFKC 正規化(半角カナ・合成濁点を畳む)してからカタカナをひらがなへ寄せる。
  # 変換表をひらがな1本に統一し、カタカナ語も同じ規則で処理できるようにする。
  def self.normalize(reading)
    reading.to_s.unicode_normalize(:nfkc).tr("ァ-ヶ", "ぁ-ゖ")
  end

  # これまでの出力の末尾側から最初に見つかる母音を返す。
  def self.last_vowel(text)
    text.reverse.each_char { |char| return char if VOWELS.include?(char) }
    nil
  end

  # 促音: 次の音の先頭子音を重ねる。ch の前は t を置く(ヘボン式。まっちゃ→matcha)。
  def self.apply_sokuon(romaji)
    return romaji unless romaji.match?(CONSONANT_HEAD)

    head = romaji.start_with?("ch") ? "t" : romaji[0]
    head + romaji
  end

  private_class_method :normalize, :last_vowel, :apply_sokuon
end
