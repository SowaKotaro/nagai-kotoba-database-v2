require "test_helper"

class RelatedWordsTest < ActiveSupport::TestCase
  test "代表語義の同ジャンル/同文字数で関連語をグループ化する" do
    subject     = make_word("関連元アイウエオカ", "アイウエオカキクケコ", genre: genres(:small_novel)) # 読み10字・先頭ア
    same_genre  = make_word("同ジャンル語サシス", "サシスセソタチツテト", genre: genres(:small_novel)) # 同ジャンル・読み10字
    same_first  = make_word("同先頭アメンボ", "アメンボアカイ")                                        # 先頭ア・読み7字
    _unrelated  = make_word("無関係ンンン", "ンンンンンンンンンンン")                                  # 別ジャンル・別長

    groups = RelatedWords.new(subject.reload).groups
    by_key = groups.index_by(&:key)

    assert_equal [ :genre, :reading_length ], groups.map(&:key)

    assert_includes by_key[:genre].words, same_genre
    assert_not_includes by_key[:genre].words, subject
    assert_equal({ genre_id: genres(:small_novel).id }, by_key[:genre].facet_params)

    assert_includes by_key[:reading_length].words, same_genre # 同じ10字
    assert_equal 10, by_key[:reading_length].facet_params[:reading_length]

    # 「同じ先頭文字」のグループは廃止した(末尾文字タグと ShiritoriWords が担う)
    assert(groups.none? { |group| group.words.include?(same_first) })
  end

  test "ジャンル未設定なら reading_length グループだけになる" do
    subject = make_word("ジャンルなし語アイウ", "アイウエオジャンル")     # 読み9字・ジャンル無し
    make_word("同じ字数の別語サシス", "サシスセソタチツテ")               # 読み9字
    keys = RelatedWords.new(subject.reload).groups.map(&:key)
    assert_equal [ :reading_length ], keys
  end

  test "各グループは自身を除外する" do
    subject = make_word("自己除外テスト", "ジコジョガイテスト", genre: genres(:small_novel))
    RelatedWords.new(subject.reload).groups.each do |group|
      assert_not_includes group.words.map(&:id), subject.id
    end
  end

  private

  def make_word(surface, reading, genre: nil)
    word = Word.create!(surface: surface, annotated_at: Time.current)
    word.word_senses.create!(reading: reading, genre: genre)
    word
  end
end
