require "test_helper"

# 共有カードの文字の組み(行の割り方と級数)。字幅は Noto Sans CJK JP の送り幅での見積もり。
class ShareCardTypesetterTest < ActiveSupport::TestCase
  STEPS = [
    ShareCardTypesetter::Step.new(lines: 1, max: 64, min: 56),
    ShareCardTypesetter::Step.new(lines: 2, max: 56, min: 42),
    ShareCardTypesetter::Step.new(lines: 3, max: 46, min: 36)
  ].freeze

  test "1行に収まらなければ割りやすい所か長さがそろう所で2行に割る(行頭禁則と WORD_JOINER を守る)" do
    assert_equal [ [ "天上天下唯我独尊" ], 64 ], layout_of("天上天下唯我独尊")
    # 全角 10 字 + 字間 9 つ = 10.27em → 606 / 10.27 = 59.0px
    assert_equal [ [ "好きこそ物の上手なれ" ], 59 ], layout_of("好きこそ物の上手なれ")
    # 半角の英字は実測の字幅で見積もるので、同じ字数の全角より大きく組める
    assert_operator fit("abcdefghij").font_size, :>, fit("あいうえおかきくけこ").font_size

    # 1 行で最小級数を割る長さになったら 2 行に割る(全角 10 字までは 1 行、11 字からは 2 行)
    assert_equal 1, fit("あ" * 10).lines.size
    assert_equal 2, fit("あ" * 11).lines.size

    # 割りやすい所(助詞の後・「・」の後・空白・開き括弧の前)があれば、そこで割る
    assert_equal [ "長い言葉の", "データベース" ], fit("長い言葉のデータベース").lines
    assert_equal [ "ノヴァ・スコシア・ダック・", "トーリング・レトリーバー" ],
                 fit("ノヴァ・スコシア・ダック・トーリング・レトリーバー").lines
    assert_equal [ "Windows 3D ピンボール", "Space Cadet" ], fit("Windows 3D ピンボール Space Cadet").lines
    assert_equal [ "Super Nintendo", "Entertainment System" ], fit("Super Nintendo Entertainment System").lines
    assert_equal [ "アアアアア", "（イイイイイ）" ], fit("アアアアア（イイイイイ）").lines

    # 割りやすい所が無ければ、行の長さがそろうように割る
    assert_equal [ "天上天下唯我", "独尊皆苦です" ], fit("天上天下唯我独尊皆苦です").lines

    # 長音符・小書きかなは行頭に置かない
    assert_equal [ "アアアアアー", "イイイイイ" ], fit("アアアアアーイイイイイ").lines
    assert_equal [ "アアアアアッ", "イイイイイ" ], fit("アアアアアッイイイイイ").lines

    # WORD_JOINER で挟んだ字のあいだでは割らず、組んだ行からは取り除く
    text = ([ "あ" * 10 ] + "（12文字）".chars).join(ShareCardTypesetter::WORD_JOINER)
    assert_equal [ "ああああああああ", "ああ（12文字）" ], fit(text).lines
  end

  test "収まらない長さは末尾を落として「…」を付け、空白だけ・制御文字は行に入れない" do
    layout = fit("あ" * 200)
    assert_equal 3, layout.lines.size
    assert layout.lines.last.end_with?("…")
    assert_equal 36, layout.font_size

    # 空白だけの文字列は行を持たず、制御文字は取り除く(SVG の XML として不正になるため)
    assert_empty fit("  ").lines
    assert_equal [ "ABC" ], fit("A\x00B\x07C").lines
  end

  private

  def fit(text)
    ShareCardTypesetter.new(text, width: 606, tracking: 0.03).fit(STEPS)
  end

  def layout_of(text)
    layout = fit(text)
    [ layout.lines, layout.font_size ]
  end
end
