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
end
