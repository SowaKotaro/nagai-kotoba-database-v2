require "test_helper"

# MeCab に依存するため、mecab が無い環境(CI・本番)では skip する。
# 集計自体がローカル実行前提の機能なので、これで運用上は困らない。
class MorphemeExtractorTest < ActiveSupport::TestCase
  setup do
    @extractor = MorphemeExtractor.new
    skip "mecab が無いため skip" unless @extractor.available?
  end

  test "漢語の複合語を部品に分ける" do
    result = @extractor.call([ "全日本大学女子駅伝対校選手権大会" ]).first
    assert_includes result, "選手権"
    assert_includes result, "大会"
    assert_includes result, "大学"
  end

  test "入力と同じ並び・同じ件数で返す" do
    result = @extractor.call([ "天上天下唯我独尊", "殺人事件" ])
    assert_equal 2, result.size
    assert_includes result.first, "天上天下"
    assert_includes result.second, "殺人"
  end

  test "空の入力には空を返す" do
    assert_equal [], @extractor.call([])
    assert_equal [], @extractor.call(nil)
  end

  test "助詞や記号は落とす" do
    result = @extractor.call([ "涼宮ハルヒの憂鬱" ]).first
    assert_not_includes result, "の"
    assert_not_includes result, "・"
  end

  test "連続するカタカナは1語に畳む" do
    # 既定辞書は「シャーロット」を知らず「シャー」+「ロット」に割ってしまう。
    # 元の表層形では地続きなので、畳んで1語として数える(本番データで上位を占めていた誤り)。
    result = @extractor.call([ "シャーロット・カタクリ" ]).first
    assert_includes result, "シャーロット"
    assert_not_includes result, "シャー"
    assert_not_includes result, "ロット"
  end

  test "区切り記号をまたいでカタカナを畳まない" do
    result = @extractor.call([ "シャーロット・カタクリ" ]).first
    assert_includes result, "カタクリ"
    assert_not_includes result, "シャーロットカタクリ"
  end

  test "数詞は落とす" do
    result = @extractor.call([ "第三次スーパーロボット大戦" ]).first
    assert_not_includes result, "三"
  end
end
