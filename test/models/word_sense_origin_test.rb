require "test_helper"

class WordSenseOriginTest < ActiveSupport::TestCase
  test "word_sense と word_origin が必要" do
    record = WordSenseOrigin.new
    assert_not record.valid?
    assert record.errors.added?(:word_sense, :blank)
    assert record.errors.added?(:word_origin, :blank)
  end

  test "同じ語義に同じ語種は二重登録できない" do
    record = WordSenseOrigin.new(word_sense: word_senses(:murder), word_origin: word_origins(:kango))
    assert_not record.valid?
    assert record.errors.added?(:word_origin_id, :taken, value: word_origins(:kango).id)
  end

  test "混種語として1語義に複数の語種を付与できる" do
    word_sense = word_senses(:murder) # 既に 漢語 が付いている
    word_sense.word_sense_origins.create!(word_origin: word_origins(:wago))
    assert_equal 2, word_sense.word_origins.count
    assert_includes word_sense.word_origins, word_origins(:kango)
    assert_includes word_sense.word_origins, word_origins(:wago)
  end
end
