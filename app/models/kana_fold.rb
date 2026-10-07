# かなの畳み込み(ひらがな⇔カタカナ)の単一の正。読み・表層形の照合順序 utf8mb4_0900_as_ci と同じく、
# かなの種類は同一視し、清濁は区別する(docs/data-model.md §6)。
#
# - 範囲は「ぁ-ゖ」⇔「ァ-ヶ」で、ゔ・ゕ・ゖ も対になる(ゔ→ヴ、ゕ→ヵ、ゖ→ヶ)。
# - NFKC は半角カナ・合成濁点(か + ゙)を全角の 1 字に畳む。正規表現のパターンのように、全角の記号を
#   半角に変えると意味が変わる入力では nfkc: false で使う(SearchRegexp)。
# - 範囲や NFKC の有無を変えると、保存済みの派生値(RhythmPattern・MoraCount → backfill:reading_metrics)・
#   共有カードの版(KanaRow 経由の円環の点)・重複チェックの結果が変わる。
# ReadingExtractor#normalize だけは、MeCab の出力をカタカナだけに絞る別の規則を持つ(ゕ・ゖ は畳まずに落とす)。
# 種別: 値オブジェクト（DB に触れない）。
module KanaFold
  HIRAGANA = "ぁ-ゖ".freeze
  KATAKANA = "ァ-ヶ".freeze

  module_function

  # ひらがなをカタカナへ寄せる(重複チェックの照合キー・50音の行・統計の集計キー・キーワードの突き合わせ)。
  def to_katakana(text, nfkc: true)
    folded = nfkc ? text.to_s.unicode_normalize(:nfkc) : text.to_s
    folded.tr(HIRAGANA, KATAKANA)
  end

  # カタカナをひらがなへ寄せる(ローマ字化・拍数。変換表をひらがな 1 本にするため)。
  def to_hiragana(text)
    text.to_s.unicode_normalize(:nfkc).tr(KATAKANA, HIRAGANA)
  end
end
