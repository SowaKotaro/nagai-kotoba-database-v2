require "test_helper"

# 一覧の並び順(値オブジェクト)。とくにシャッフルのシードの扱いを固定する。
# シードを URL(href)側で振っていた頃は、一覧を描画するたびに未知の URL が生まれ、
# クローラが無限に新しい URL を辿れてしまっていた。シードはサーバ側だけで持つ。
class WordSortTest < ActiveSupport::TestCase
  test "未知のキーは既定(収録が新しい順)に畳む" do
    assert_equal WordSort::DEFAULT_KEY, WordSort.new("../../etc/passwd").key
    assert_equal WordSort::DEFAULT_KEY, WordSort.new(nil).key
    assert WordSort.new(nil).default?
  end

  test "シード無しのシャッフルは呼ぶたびに新しいシードを振る" do
    seeds = 5.times.map { WordSort.new("shuffle").seed }
    assert_equal 5, seeds.uniq.size, "同じシードが返ると開き直しても並びが変わらない"
    assert seeds.all?(&:present?)
  end

  test "URL から渡されたシードはそのまま使う(ページ送りで並びが保たれる)" do
    assert_equal "abc123", WordSort.new("shuffle", seed: "abc123").seed
  end

  test "長すぎるシードは切り詰める" do
    assert_equal WordSort::SEED_LIMIT, WordSort.new("shuffle", seed: "a" * 100).seed.length
  end

  test "シャッフル以外はシードを持たない" do
    assert_nil WordSort.new("kana_asc").seed
    assert_nil WordSort.new("kana_asc", seed: "abc123").seed
  end

  test "シャッフルの ORDER BY はシードを埋め込んでも SQL を壊さない" do
    clause = WordSort.new("shuffle", seed: "a'b\"c").order_clause.to_s
    assert_includes clause, "MD5(CONCAT(words.id,"
    # 生の引用符がそのまま出ていない(サニタイズされている)こと
    assert_not_includes clause, %(a'b"c)
  end
end
