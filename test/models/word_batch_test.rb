require "test_helper"

class WordBatchTest < ActiveSupport::TestCase
  setup do
    @words = %w[ウ語の候補 ア語の候補 イ語の候補].map do |surface|
      create_published_word(surface: surface, reading: "#{surface}ノヨミノナガイヨミ", genre: genres(:small_novel))
    end
    @ids = @words.map(&:id)
  end

  test "預けた id を区画ごとに表層形の順で、1回の読み込みでまとめて返す" do
    batch = WordBatch.new
    first  = batch.reserve(@ids[0, 2])
    second = batch.reserve(@ids[1, 2])

    assert_equal %w[ア語の候補 ウ語の候補], batch.words_for(first).map(&:surface)
    assert_equal %w[ア語の候補 イ語の候補], batch.words_for(second).map(&:surface)

    # 複数の区画の語を1回の読み込みでまとめて引き、パンくずの祖先まで先読みしておく
    batch = WordBatch.new
    first  = batch.reserve(@ids[0, 1])
    second = batch.reserve(@ids[1, 2])
    batch.words_for(first) # ここでまとめて読む

    assert_no_queries do
      loaded_words = batch.words_for(second)
      loaded_words.each { |word| word.word_senses.each { |sense| sense.genre.parent.parent } }
    end

    # 読み込んだ後に預けた id も取りこぼさない
    batch = WordBatch.new
    first = batch.reserve(@ids[0, 1])
    batch.words_for(first)
    late = batch.reserve(@ids[2, 1])

    assert_equal [ "イ語の候補" ], batch.words_for(late).map(&:surface)

    # 空の id には空を返し、読み込みもしない
    assert_no_queries { assert_equal [], WordBatch.new.words_for([]) }
  end
end
