require "test_helper"

# 単語の共有カード(og:image)の SVG。PNG に焼くところは ShareCardRendererTest。
class WordShareCardTest < ActiveSupport::TestCase
  test "表層形・読みと文字数・標識を描き、円環は読みを読み順に結ぶ" do
    card = WordShareCard.new(words(:abc_murder))
    svg = parse(card.svg)

    assert_equal [ "ABC殺人事件", "さつじんじけん（7文字）", "NAGAI-KOTOBA-DATABASE.JP", "READING / 7 CHARACTERS" ],
                 svg.css("text").map(&:text)
    assert_equal KanaRing.path("さつじんじけん").size, svg.at_css("polyline")["points"].split.size
  end

  test "表層形の & や < はエスケープされ、XML として正しく読める" do
    word = Word.new(surface: "A&B<C>")
    word.word_senses.build(reading: "エーアンドビーシー")

    assert_includes parse(WordShareCard.new(word).svg).css("text").map(&:text), "A&B<C>"
  end

  test "版は描いた中身から決まり、表層形が変われば変わる" do
    word = words(:abc_murder)
    digest = WordShareCard.new(word).digest
    assert_equal digest, WordShareCard.new(word).digest

    word.surface = "ABC殺人事件簿"
    assert_not_equal digest, WordShareCard.new(word).digest
  end

  test "語義(読み)の無い語は描けない" do
    assert_not WordShareCard.new(Word.new(surface: "語義の無い言葉")).drawable?
    assert WordShareCard.new(words(:abc_murder)).drawable?
  end

  test "いちばん長くなる組み(表層形も読みも最後の候補まで行を増やす)でも、文字は枠の内側に収まる" do
    word = Word.new(surface: "あ" * 200)
    word.word_senses.build(reading: "ア" * 200)
    card = WordShareCard.new(word)

    assert_equal WordShareCard::SURFACE_STEPS.last.lines, card.surface_lines.size
    assert_equal WordShareCard::READING_STEPS.last.lines, card.reading_lines.size
    assert_operator card.surface_lines.first.y - card.surface_font_size * WordShareCard::ASCENT, :>, WordShareCard::FRAME_TOP
    assert_operator card.label_lines.last.y, :<, WordShareCard::FRAME_BOTTOM
  end

  private

  # 不正な XML なら例外にする(rsvg-convert は壊れた SVG を焼けない)
  def parse(svg)
    Nokogiri::XML(svg, &:strict).remove_namespaces!
  end
end
