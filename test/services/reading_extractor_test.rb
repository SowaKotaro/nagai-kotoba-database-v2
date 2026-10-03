require "test_helper"

# MeCab の CLI を呼ぶサービス。mecab が無い環境(一部の CI 等)では skip する。
class ReadingExtractorTest < ActiveSupport::TestCase
  test "空配列には空配列を返す" do
    assert_equal [], ReadingExtractor.call([])
  end

  # mecab が無い環境の退避。判定はプロセスごとにメモするので、PATH を変えず available? を差し替える。
  test "mecab が無いときは、入力と同じ数の nil を返す" do
    stub_method(ReadingExtractor, :available?, -> { false }) do
      assert_equal [ nil, nil ], ReadingExtractor.call([ "天上天下唯我独尊", "資本主義" ])
    end
  end

  # 判定のあとで mecab が消えた(起動に失敗した)ときも止めない。
  test "判定が真でも起動できなければ、入力と同じ数の nil を返す" do
    original_path = ENV["PATH"]
    ENV["PATH"] = ""
    stub_method(ReadingExtractor, :available?, -> { true }) do
      assert_equal [ nil, nil ], ReadingExtractor.call([ "天上天下唯我独尊", "資本主義" ])
    end
  ensure
    ENV["PATH"] = original_path
  end

  test "表層形の並びに対応した読み(カタカナ)を返す" do
    skip "mecab 未インストールのため skip" unless ReadingExtractor.available?

    surfaces = [ "天上天下唯我独尊", "資本主義" ]
    readings = ReadingExtractor.call(surfaces)

    assert_equal surfaces.size, readings.size
    assert_equal "テンジョウテンゲユイガドクソン", readings[0]
    assert_match(/\A[゠-ヿ]+\z/, readings[1]) # カタカナ
  end

  test "中黒などの記号は読みから落とす" do
    skip "mecab 未インストールのため skip" unless ReadingExtractor.available?

    assert_equal "シャーロットリンリン", ReadingExtractor.call([ "シャーロット・リンリン" ]).first
  end

  test "全角英数字の語も半角に寄せて読みを取る" do
    skip "mecab 未インストールのため skip" unless ReadingExtractor.available?

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

  # かなの畳み込み(T0-18): NFKC で畳み、ひらがなは「ぁ-んゔ」の範囲だけカタカナにする。ゕ・ゖ は落ちる。
  test "読みの整形は半角カナ・合成濁点・ゔ を畳み、ゕ・ゖ を落とす" do
    assert_equal "ガギガヴ", normalize(ReadingExtractor.new, KANA_FOLD_SAMPLE)
  end

  private

  def normalize(extractor, line) = extractor.normalize(line)
end
