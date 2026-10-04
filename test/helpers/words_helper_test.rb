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

  # --- X 共有の本文(投稿上限 280 単位 = 全角 128 文字に収める) ---
  test "X共有本文: 短いリード文はそのまま使う" do
    word = words(:curry)
    lead = word_lead_sentence(word)
    assert_equal lead, x_share_text(word, lead)
  end

  test "X共有本文: 長いリード文は上限で切り詰めて省略記号を付ける" do
    text = x_share_text(words(:abc_murder), "あ" * 200)
    assert_equal WordsHelper::X_SHARE_TEXT_LIMIT, text.length
    assert text.end_with?("…")
  end

  test "X共有本文: リード文が無ければ見出し語を使う" do
    word = words(:abc_murder)
    assert_equal word.surface, x_share_text(word, "")
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
    word = Word.create!(surface: "一日", annotated_at: Time.current)
    word.word_senses.create!(reading: "イチニチ", meaning: "24時間。")
    word.word_senses.create!(reading: "ツイタチ", meaning: "月の第1日。")

    expected = "「一日」は、読み「イチニチ」「ツイタチ」の日本語の長い言葉。" \
               "語義は2つ。① 24時間。② 月の第1日。"
    assert_equal expected, word_lead_sentence(word)
  end

  private

  # 同じ読みで意味の異なる語義を持つ語(同音異義語)を作る。
  def multi_sense_word(*sense_attrs)
    word = Word.create!(surface: "ピーターパンシンドローム", annotated_at: Time.current)
    sense_attrs.each do |attrs|
      word.word_senses.create!(reading: "ピーターパンシンドローム", **attrs)
    end
    word
  end

  # かなの畳み込み(T0-18): NFKC をかけないので半角カナと合成濁点は残る。欧字は小文字にする。
  test "キーワード突き合わせの畳み込みは、ひらがなをカタカナへ寄せ、欧字を小文字にするだけ" do
    expected = [ 0xFF76, 0xFF9E, 0xFF77, 0xFF9E, 0x30AB, 0x3099, 0x30F4, 0x30F5, 0x30F6 ].pack("U*") + "abc"
    assert_equal expected, fold_for_keyword_match(KANA_FOLD_SAMPLE + "ABC")
  end
end
