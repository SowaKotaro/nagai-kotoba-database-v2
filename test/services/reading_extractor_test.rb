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
end
