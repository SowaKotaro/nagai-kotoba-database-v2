require "test_helper"

# MeCab の CLI を呼ぶサービス。mecab が無い環境(一部の CI 等)では skip する。
class ReadingExtractorTest < ActiveSupport::TestCase
  def mecab_available?
    system("mecab", "--version", out: File::NULL, err: File::NULL)
  end

  test "空配列には空配列を返す" do
    assert_equal [], ReadingExtractor.call([])
  end

  test "表層形の並びに対応した読み(カタカナ)を返す" do
    skip "mecab 未インストールのため skip" unless mecab_available?

    surfaces = [ "天上天下唯我独尊", "資本主義" ]
    readings = ReadingExtractor.call(surfaces)

    assert_equal surfaces.size, readings.size
    assert_equal "テンジョウテンゲユイガドクソン", readings[0]
    assert_match(/\A[゠-ヿ]+\z/, readings[1]) # カタカナ
  end

  test "中黒などの記号は読みから落とす" do
    skip "mecab 未インストールのため skip" unless mecab_available?

    assert_equal "シャーロットリンリン", ReadingExtractor.call([ "シャーロット・リンリン" ]).first
  end

  test "全角英数字の語も半角に寄せて読みを取る" do
    skip "mecab 未インストールのため skip" unless mecab_available?

    assert_equal ReadingExtractor.call([ "Dr.スランプ" ]), ReadingExtractor.call([ "Ｄｒ．スランプ" ])
  end

  # mecab の出力を整える部分は辞書に依存しないため、直接検証する。
  test "カタカナ以外(記号・英数字・空白)を除き、ひらがな・半角カナはカタカナに寄せる" do
    extractor = ReadingExtractor.new

    assert_equal "シャーロットリンリン", normalize(extractor, "シャーロット・リンリン")
    assert_equal "ロングロングロング", normalize(extractor, "ロング＆ロング ロング")
    assert_equal "プニプニ", normalize(extractor, "ぷにぷに")
    assert_equal "シャーロット", normalize(extractor, "ｼｬｰﾛｯﾄ")
    assert_equal "ヴァイオリン", normalize(extractor, "ゔぁいおりん")
    assert_nil normalize(extractor, "Dr.")
    assert_nil normalize(extractor, "")
  end

  private

  def normalize(extractor, line) = extractor.send(:normalize, line)
end
