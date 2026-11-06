require "test_helper"

# 単語の共有カード(og:image)の SVG。PNG に焼くところは ShareCardRendererTest。
class WordShareCardTest < ActiveSupport::TestCase
  test "壁・文字数・表層形・読み・説明・ジャンルと品詞の札を描き、円環は読みを読み順に結ぶ" do
    card = WordShareCard.new(words(:abc_murder))
    svg = parse(card.svg)
    texts = svg.css("text").map(&:text)
    wall = ShareCardWall.default.items.map(&:text)

    assert_equal wall, texts.first(wall.size)
    assert_equal [ "7", "字", "ABC殺人事件", "さつじんじけん", "人を殺す事件", "小説", "名詞" ], texts.drop(wall.size)
    assert_equal KanaRing.path("さつじんじけん").size, svg.at_css("polyline")["points"].split.size
    assert_equal 2, svg.css("rect[stroke-width='2']").size - 1 # 札の枠 1 枚のほかに、ジャンルと品詞の札
  end

  test "説明もジャンルも品詞も無い語は、罫も札も出さず、表層形と読みだけを中央に置く" do
    word = Word.new(surface: "活版印刷術")
    word.word_senses.build(reading: "カッパンインサツジュツ")
    card = WordShareCard.new(word)

    assert_nil card.rule_y
    assert_empty card.meaning_lines
    assert_empty card.chips
    assert_in_delta WordShareCard::FRAME_MIDDLE, (card.surface_lines.first.y - WordShareCard::ASCENT * card.surface_font_size +
                                                   card.reading_lines.last.y + WordShareCard::DESCENT * card.reading_font_size) / 2.0, 1.0
  end

  test "説明は 2 行までで、収まらない分は末尾を「…」で落とす" do
    word = Word.new(surface: "活版印刷術")
    word.word_senses.build(reading: "カッパンインサツジュツ", meaning: "あ" * 300)
    card = WordShareCard.new(word)

    assert_equal WordShareCard::MEANING_LINES, card.meaning_lines.size
    assert card.meaning_lines.last.text.end_with?(ShareCardTypesetter::ELLIPSIS)
    assert_operator card.meaning_font_size, :>=, WordShareCard::MEANING_MIN
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

  # 版は og:image の URL に入るので、SVG のバイト列が 1 つでも変わると、共有済みの URL ごと変わる。
  # リファクタリング(大規模改修)のあいだ、カードの入力(代表語義・説明・ジャンルと品詞・円環の点・壁・テンプレート)に触れても
  # 版が変わらないことを確かめるための値。意匠を意図して変えたときは、ここを新しい値に更新する。
  test "フィクスチャの語の版は、いまの値のまま" do
    assert_equal "e9bb6425042787a9", WordShareCard.new(words(:abc_murder)).digest
    assert_equal "c469085e6161b034", WordShareCard.new(words(:curry)).digest
  end

  test "語義(読み)の無い語は描けない" do
    assert_not WordShareCard.new(Word.new(surface: "語義の無い言葉")).drawable?
    assert WordShareCard.new(words(:abc_murder)).drawable?
  end

  test "焼けるのは、描ける語で、かつ rsvg-convert と日本語の書体がある環境だけ" do
    stub_method(ShareCardRenderer, :available?, -> { true }) do
      assert WordShareCard.new(words(:abc_murder)).renderable?
      assert_not WordShareCard.new(Word.new(surface: "語義の無い言葉")).renderable?
    end
    stub_method(ShareCardRenderer, :available?, -> { false }) do
      assert_not WordShareCard.new(words(:abc_murder)).renderable?
    end
  end

  test "いちばん長くなる組み(表層形も読みも最後の候補まで行を増やし、説明も 2 行)でも、文字は枠の内側に余白を残して収まる" do
    word = Word.new(surface: "あ" * 200)
    word.word_senses.build(reading: "ア" * 200, meaning: "い" * 300, genre: genres(:small_novel), part_of_speech: parts_of_speech(:noun))
    card = WordShareCard.new(word)
    margin = WordShareCard::BLOCK_MARGIN

    assert_equal WordShareCard::SURFACE_STEPS.last.lines, card.surface_lines.size
    assert_equal WordShareCard::READING_STEPS.last.lines, card.reading_lines.size
    assert_operator card.surface_lines.first.y - card.surface_font_size * WordShareCard::ASCENT, :>=, WordShareCard::FRAME_TOP + margin - 1
    lowest = card.chips.map { |chip| chip.y + WordShareCard::CHIP_HEIGHT }.max ||
             card.meaning_lines.last&.y || card.reading_lines.last.y
    assert_operator lowest, :<=, WordShareCard::FRAME_BOTTOM - margin + 1
  end

  private

  # 不正な XML なら例外にする(rsvg-convert は壊れた SVG を焼けない)
  def parse(svg)
    Nokogiri::XML(svg, &:strict).remove_namespaces!
  end
end
