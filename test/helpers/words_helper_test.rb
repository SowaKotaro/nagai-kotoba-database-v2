require "test_helper"

class WordsHelperTest < ActionView::TestCase
  test "リード文: 読み・文字数・モーラ・ジャンル・意味を散文化する" do
    word = words(:abc_murder)
    expected = "「ABC殺人事件」は、読み「さつじんじけん」（7文字・7モーラ）の日本語の長い言葉。" \
               "ジャンルは 文学 › 日本文学 › 小説。人を殺す事件"
    assert_equal expected, word_lead_sentence(word)
  end

  test "リード文: ジャンル・意味が無ければ省く" do
    word = words(:curry)
    expected = "「カレーライス」は、読み「カレー」（3文字・3モーラ）の日本語の長い言葉。"
    assert_equal expected, word_lead_sentence(word)
  end

  test "リード文: モーラ数が無ければ文字数のみを添える" do
    word = words(:curry)
    word.word_senses.min_by(&:id).mora_count = nil
    expected = "「カレーライス」は、読み「カレー」（3文字）の日本語の長い言葉。"
    assert_equal expected, word_lead_sentence(word)
  end

  test "リード文: 語義が無ければ空文字を返す" do
    assert_equal "", word_lead_sentence(Word.new(surface: "無語義"))
  end

  # --- 複数語義(同音異義語)。先頭語義だけを見ず、意味を①②…で並べる ---
  test "リード文: 複数語義は語義数と各語義の意味を番号付きで並べる" do
    word = multi_sense_word(
      { meaning: "大人になれない男性の心理傾向を指す通俗心理学の用語。", genre: genres(:small_novel) },
      { meaning: "日本の男性アイドルグループ。" }
    )
    expected = "「ピーターパンシンドローム」は、読み「ピーターパンシンドローム」（12文字・12モーラ）の日本語の長い言葉。" \
               "語義は2つ。① 大人になれない男性の心理傾向を指す通俗心理学の用語。② 日本の男性アイドルグループ。"
    assert_equal expected, word_lead_sentence(word)
  end

  test "リード文: 複数語義では意味の句点が無ければ補う" do
    word = multi_sense_word({ meaning: "通俗心理学の用語" }, { meaning: "男性アイドルグループ" })
    assert_equal "語義は2つ。① 通俗心理学の用語。② 男性アイドルグループ。", word_lead_sentence(word).split("言葉。").last
  end

  test "リード文: 意味が未登録の語義は飛ばし、番号は詰めない" do
    word = multi_sense_word({ meaning: nil }, { meaning: "日本の男性アイドルグループ。" })
    assert_equal "語義は2つ。② 日本の男性アイドルグループ。", word_lead_sentence(word).split("言葉。").last
  end

  test "リード文: 語義ごとに読みが違えば読みを並べ、文字数・モーラは添えない" do
    word = Word.create!(surface: "一日", char_type_pattern: "漢漢", annotated_at: Time.current)
    word.word_senses.create!(reading: "イチニチ", mora_count: 4, meaning: "24時間。")
    word.word_senses.create!(reading: "ツイタチ", mora_count: 4, meaning: "月の第1日。")

    expected = "「一日」は、読み「イチニチ」「ツイタチ」の日本語の長い言葉。" \
               "語義は2つ。① 24時間。② 月の第1日。"
    assert_equal expected, word_lead_sentence(word)
  end

  private

  # 同じ読みで意味の異なる語義を持つ語(同音異義語)を作る。
  def multi_sense_word(*sense_attrs)
    word = Word.create!(surface: "ピーターパンシンドローム", char_type_pattern: "ア" * 12,
                        annotated_at: Time.current)
    sense_attrs.each do |attrs|
      word.word_senses.create!(reading: "ピーターパンシンドローム", mora_count: 12, **attrs)
    end
    word
  end
end
