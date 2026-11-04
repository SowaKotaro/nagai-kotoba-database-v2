require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "説明文は文ごとの塊に、名前と用語解説の例は折ってよい切れ目で切った塊に組み、塊の末尾の空白は塊の外に残す" do
    sentences = Nokogiri::HTML5.fragment(phrased_sentences([ [ "「大分類」の棒 → ", "中分類の棒を" ], [ "押します。" ] ]))
    assert_equal [ "「大分類」の棒 → 中分類の棒を", "押します。" ], sentences.css(".phrase-sentence").map(&:text)
    assert_equal [ "「大分類」の棒 →", "中分類の棒を", "押します。" ], sentences.css(".phrase").map(&:text)

    name = Nokogiri::HTML5.fragment(phrased_name("雑誌・逐次刊行物（カレンダー含む） 全体を見る"))
    assert_equal [ "雑誌・", "逐次刊行物", "（カレンダー含む）", "全体を見る" ], name.css(".phrase").map(&:text)
    assert_equal "雑誌・逐次刊行物（カレンダー含む） 全体を見る", name.text
    assert_equal 3, name.css("wbr").size

    # 用語解説の例は、区切りを丸ごと前の例に、ラベルを最初の例に含めた塊にする(「／」やラベルだけの行を作らない)。
    # 例の中は演算子の後ろ・「・」の後ろ・括弧書きの前と、括弧書きの中の句読点の後ろで切る(括弧書きの中の空白と半角の括弧では切らない)
    separator = I18n.t("shared.feature_glossary.examples_separator")
    list = [ "菅(すが) + 原(はら) → すがわら（ハラ → ワラ）", "熱さまし + シート → ねつさましーと（熱さまシート。「シ」を1つにまとめる）",
             "青眼の白龍 → ブルーアイズ・ホワイト・ドラゴン" ]
    examples = Nokogiri::HTML5.fragment(feature_examples(list, label: "例: "))
    chunks = examples.children.select { |node| node["class"] == "phrase" }
    assert_equal [ "例: #{list[0]}#{separator}", "#{list[1]}#{separator}", list[2] ], chunks.map(&:text)
    assert_equal [ [ "例: 菅(すが) +", "原(はら) →", "すがわら", "（ハラ → ワラ）#{separator}" ],
                   [ "熱さまし +", "シート →", "ねつさましーと", "（熱さまシート。", "「シ」を1つにまとめる）#{separator}" ],
                   [ "青眼の白龍 →", "ブルーアイズ・", "ホワイト・", "ドラゴン" ] ],
                 chunks.map { |chunk| chunk.css("> .phrase").map(&:text) }
    assert_equal [ separator, separator ], examples.css(".phrase-mark").map(&:text)
    assert_equal "例: #{list.join(separator)}", examples.text
  end
end
