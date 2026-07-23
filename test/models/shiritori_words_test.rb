require "test_helper"

class ShiritoriWordsTest < ActiveSupport::TestCase
  test "末尾文字を先頭文字に持つ公開語を次の一手として返す" do
    subject = make_word("しりとり起点の言葉", "シリトリキテンノコトバ")   # 末尾 バ
    next_word = make_word("バーコードバトラー", "バーコードバトラー")     # 先頭 バ
    other     = make_word("無関係の長い言葉", "ムカンケイノナガイコトバ") # 先頭 ム

    shiritori = ShiritoriWords.new(subject.reload)

    assert_equal "バ", shiritori.head_char
    assert_not shiritori.dead_end?
    assert_includes shiritori.words, next_word
    assert_not_includes shiritori.words, other
    assert_equal({ first_char: "バ" }, shiritori.facet_params)
  end

  test "自身は次の一手に含めない" do
    # 「ル」で始まり「ル」で終わる語は自分自身に繋がってしまうため除外する
    subject = make_word("ルーレットのループル", "ルーレットノループル")
    other   = make_word("ルビーの指輪の値段", "ルビーノユビワノネダン")

    shiritori = ShiritoriWords.new(subject.reload)

    assert_equal "ル", shiritori.head_char
    assert_includes shiritori.words, other
    assert_not_includes shiritori.words, subject
  end

  test "未注釈の語は次の一手に出ない" do
    subject = make_word("しりとり起点の言葉", "シリトリキテンノコトバ") # 末尾 バ
    unannotated = Word.create!(surface: "未注釈のバナナ")
    unannotated.word_senses.create!(reading: "バナナオオモリセット")

    assert_not_includes ShiritoriWords.new(subject.reload).words, unannotated
  end

  test "末尾の長音符は直前の文字から繋ぐ(last_char の仕様)" do
    subject = make_word("エスプレッソコーヒー", "エスプレッソコーヒー") # 末尾 ー → ヒ
    next_word = make_word("ヒエラルキーの頂点", "ヒエラルキーノチョウテン")

    shiritori = ShiritoriWords.new(subject.reload)

    assert_equal "ヒ", shiritori.head_char
    assert_includes shiritori.words, next_word
  end

  test "小書き・ひらがなの違いは照合順序(as_ci)で吸収する" do
    subject = make_word("ぬるぬるのおもちゃ", "ヌルヌルノオモチャ")     # 末尾 ャ
    next_word = make_word("やまびこのこだま", "やまびこのこだまだま")   # 先頭 や

    shiritori = ShiritoriWords.new(subject.reload)

    assert_equal "ャ", shiritori.head_char
    assert_includes shiritori.words, next_word
  end

  test "清濁は区別する(「バ」で終わったら「ハ」始まりには繋がない)" do
    subject = make_word("しりとり起点の言葉", "シリトリキテンノコトバ") # 末尾 バ
    seion   = make_word("ハンドルネームの人", "ハンドルネームノヒト")   # 先頭 ハ

    assert_not_includes ShiritoriWords.new(subject.reload).words, seion
  end

  test "「ん」で終わる語は行き止まりで候補を引かない" do
    subject = make_word("ABC殺人事件のはん", "エービーシーサツジンジケンノハン")
    make_word("ンジャメナの街並み", "ンジャメナノマチナミ") # ン始まりの語があっても繋がない

    shiritori = ShiritoriWords.new(subject.reload)

    assert_equal "ン", shiritori.head_char
    assert shiritori.dead_end?
    assert_empty shiritori.words
  end

  test "語義が無い語では起点文字を持たない" do
    word = Word.create!(surface: "語義なしの言葉", annotated_at: Time.current)

    shiritori = ShiritoriWords.new(word.reload)

    assert_nil shiritori.head_char
    assert_not shiritori.dead_end?
    assert_empty shiritori.words
  end

  private

  def make_word(surface, reading)
    word = Word.create!(surface: surface, annotated_at: Time.current)
    word.word_senses.create!(reading: reading)
    word
  end
end
