# 読み(reading, かな)のモーラ(拍)数を数える値オブジェクト。
# 「きゃ」のような拗音は1拍として数える点が reading_length(CHAR_LENGTH)と異なる。
# 生成は Ruby 側で行い、WordSense の before_validation で自動セットする(手入力させない)。
#
# 方針:
#   - モーラ数 = 正規化後の文字数 - 拗音を作る小書きかなの数。
#   - 拗音を作る小書きかな(ぁぃぅぇぉ ゃゅょ ゎ)は直前の音に併合するため数えない。
#   - 促音 っ・長音符 ー・撥音 ん はそれぞれ独立した1拍なので数える(除外しない)。
#   - 変換表に無い文字(記号など)は reading_length と同様に1文字=1拍として数える。
class MoraCount
  # 前の音に併合する小書きかな。促音 っ は独立した拍なので含めない。
  SMALL_KANA = "ぁぃぅぇぉゃゅょゎ".chars.freeze

  # reading からモーラ数を返す。nil / 空文字は 0。
  def self.call(reading)
    normalize(reading).chars.count { |char| !SMALL_KANA.include?(char) }
  end

  # NFKC 正規化(半角カナ・合成濁点を畳む)してからカタカナをひらがなへ寄せる。
  # RhythmPattern と同じ正規化にそろえ、カナ表記でも同じ結果を得る。
  def self.normalize(reading)
    reading.to_s.unicode_normalize(:nfkc).tr("ァ-ヶ", "ぁ-ゖ")
  end

  private_class_method :normalize
end
