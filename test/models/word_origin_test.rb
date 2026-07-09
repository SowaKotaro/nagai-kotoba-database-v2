require "test_helper"

class WordOriginTest < ActiveSupport::TestCase
  test "name が空だと無効" do
    word_origin = WordOrigin.new(name: "")
    assert_not word_origin.valid?
    assert word_origin.errors.added?(:name, :blank)
  end

  test "name は一意" do
    dup = WordOrigin.new(name: word_origins(:wago).name)
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: word_origins(:wago).name)
  end

  test "name が異なれば有効" do
    assert WordOrigin.new(name: "タミル語").valid?
  end

  test "word_senses を多対多で辿れる" do
    assert_includes word_origins(:kango).word_senses, word_senses(:murder)
  end

  test "語義から参照されている語種は削除できない" do
    origin = word_origins(:kango)
    assert_not origin.destroy
    assert WordOrigin.exists?(origin.id)
    assert origin.errors.of_kind?(:base, :"restrict_dependent_destroy.has_many")
  end

  test "参照されていない語種は削除できる" do
    origin = WordOrigin.create!(name: "タミル語")
    assert origin.destroy
  end

  # --- タグ統括管理 ---
  test "usage_count は付与している語義数を返す" do
    assert_equal 1, word_origins(:kango).usage_count
    assert_equal 0, word_origins(:wago).usage_count
  end

  test "未使用は削除でき、使用中は削除できない" do
    assert word_origins(:wago).deletable?
    assert_not word_origins(:kango).deletable?
  end

  test "merge_into! は中間表を付け替える" do
    word_origins(:eigo).merge_into!(word_origins(:wago))
    assert_not WordOrigin.exists?(word_origins(:eigo).id)
    assert_includes word_senses(:curry).reload.word_origins, word_origins(:wago)
  end

  test "merge_into! は付け替え先に既に同じ語義があれば重複を作らない" do
    # murder は kango を持つ。murder に wago も付けてから kango→wago 統合すると、
    # 既に wago があるため重複を作らず1つにまとまる。
    WordSenseOrigin.create!(word_sense: word_senses(:murder), word_origin: word_origins(:wago))
    word_origins(:kango).merge_into!(word_origins(:wago))
    assert_not WordOrigin.exists?(word_origins(:kango).id)
    assert_equal 1, WordSenseOrigin.where(word_sense: word_senses(:murder), word_origin: word_origins(:wago)).count
  end
end
