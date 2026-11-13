require "test_helper"

class WordsHelperTest < ActionView::TestCase
  test "リード文: 単一語義は読み・文字数・モーラ・ジャンル・意味を散文化し、無いものは省く" do
    word = words(:abc_murder)
    expected = "「ABC殺人事件」は、読み「さつじんじけん」（7文字・7モーラ）の日本語の長い言葉。" \
               "ジャンルは 文学 › 日本文学 › 小説。人を殺す事件"
    assert_equal expected, word_lead_sentence(word)

    # リード文: ジャンル・意味が無ければ省く
    word = words(:curry)
    expected = "「カレーライス」は、読み「カレー」（3文字・3モーラ）の日本語の長い言葉。"
    assert_equal expected, word_lead_sentence(word)

    # リード文: モーラ数が無ければ文字数のみを添える
    word = words(:curry)
    word.word_senses.min_by(&:id).mora_count = nil
    expected = "「カレーライス」は、読み「カレー」（3文字）の日本語の長い言葉。"
    assert_equal expected, word_lead_sentence(word)

    # リード文: 語義が無ければ空文字を返す
    assert_equal "", word_lead_sentence(Word.new(surface: "無語義"))
  end

  test "ファセット面の description: 件数と先頭の語を例に入れ、長すぎる例は並べない" do
    word = ->(surface) { Word.new(surface: surface) }
    long = "あ" * (WordsHelper::FACET_EXAMPLES_MAX_LENGTH - 2) # かぎ括弧を足して、ちょうど上限
    {
      # 先頭から上限の数まで
      [ 1234, %w[甲 乙 丙 丁] ] => "読みが10文字の長い言葉の一覧（1,234語）。「甲」「乙」「丙」など。",
      # 上限の長さを超える語の手前で止める(途中で切らない)
      [ 2, [ long, "乙" ] ] => "読みが10文字の長い言葉の一覧（2語）。「#{long}」など。",
      # 1 語目から収まらないときと、0 件のときは、件数だけの文にする
      [ 1, [ "#{long}あ" ] ] => "読みが10文字の長い言葉の一覧（1語）。",
      [ 0, [] ] => "読みが10文字の長い言葉の一覧（0語）。"
    }.each do |(count, surfaces), expected|
      assert_equal expected, facet_meta_description("読みが10文字の長い言葉", count, surfaces.map(&word))
    end
  end

  # --- X 共有の本文(投稿上限 280 単位 = 全角 128 文字に収める) ---
  test "X共有本文はリード文を上限で切り詰め、無ければ見出し語を使う" do
    word = words(:curry)
    lead = word_lead_sentence(word)
    assert_equal lead, x_share_text(word, lead)

    # X共有本文: 長いリード文は上限で切り詰めて省略記号を付ける
    text = x_share_text(words(:abc_murder), "あ" * 200)
    assert_equal WordsHelper::X_SHARE_TEXT_LIMIT, text.length
    assert text.end_with?("…")

    # X共有本文: リード文が無ければ見出し語を使う
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
    word = create_published_word(surface: "一日", reading: "イチニチ", meaning: "24時間。")
    word.word_senses.create!(reading: "ツイタチ", meaning: "月の第1日。")

    expected = "「一日」は、読み「イチニチ」「ツイタチ」の日本語の長い言葉。" \
               "語義は2つ。① 24時間。② 月の第1日。"
    assert_equal expected, word_lead_sentence(word)
  end

  private

  # 同じ読みで意味の異なる語義を持つ語(同音異義語)を作る。
  def multi_sense_word(*sense_attrs)
    first, *rest = sense_attrs
    word = create_published_word(surface: "ピーターパンシンドローム", reading: "ピーターパンシンドローム", **first)
    rest.each { |attrs| word.word_senses.create!(reading: "ピーターパンシンドローム", **attrs) }
    word
  end

  test "検索に当たった箇所を mark で囲み、重なった箇所は濃くし、ほかの字はエスケープしたまま残す" do
    assert_equal "A<b>C", search_highlighted("A<b>C", [])
    assert_equal "A<b>C", search_highlighted("A<b>C", nil)
    spans = [ SearchHighlight::Span.new(range: 0...2, deep: false), SearchHighlight::Span.new(range: 3...5, deep: true) ]
    assert_equal %(<mark class="search-hit">A&lt;</mark>b<mark class="search-hit search-hit--deep">&gt;C</mark>),
                 search_highlighted("A<b>C", spans)
  end
end
