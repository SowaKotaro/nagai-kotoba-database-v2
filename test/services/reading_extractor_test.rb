require "test_helper"

# MeCab の CLI を呼ぶサービス。mecab が無い環境(一部の CI 等)では skip する。
class ReadingExtractorTest < ActiveSupport::TestCase
  test "mecab が無い・起動できなければ、入力と同じ数の nil を返す" do
    assert_equal [], ReadingExtractor.call([])

    # mecab が無いときは、入力と同じ数の nil を返す
    # mecab が無い環境の退避。判定はプロセスごとにメモするので、PATH を変えず available? を差し替える。
    stub_method(ReadingExtractor, :available?, -> { false }) do
      assert_equal [ nil, nil ], ReadingExtractor.call([ "天上天下唯我独尊", "資本主義" ])
    end

    # 判定が真でも起動できなければ、入力と同じ数の nil を返す
    # 判定のあとで mecab が消えた(起動に失敗した)ときも止めない。
    with_env("PATH" => "") do
      stub_method(ReadingExtractor, :available?, -> { true }) do
        assert_equal [ nil, nil ], ReadingExtractor.call([ "天上天下唯我独尊", "資本主義" ])
      end
    end
  end

  test "表層形の並びに対応したカタカナの読みを返し、記号を落として全角英数字も読む" do
    skip "mecab 未インストールのため skip" unless ReadingExtractor.available?

    surfaces = [ "天上天下唯我独尊", "資本主義" ]
    readings = ReadingExtractor.call(surfaces)

    assert_equal surfaces.size, readings.size
    assert_equal "テンジョウテンゲユイガドクソン", readings[0]
    assert_match(/\A[゠-ヿ]+\z/, readings[1]) # カタカナ

    # 中黒などの記号は読みから落とす
    assert_equal "シャーロットリンリン", ReadingExtractor.call([ "シャーロット・リンリン" ]).first

    # 全角英数字の語も半角に寄せて読みを取る
    assert_equal ReadingExtractor.call([ "Dr.スランプ" ]), ReadingExtractor.call([ "Ｄｒ．スランプ" ])
  end

  # mecab の出力を整える部分は辞書に依存しないため、直接検証する。
  test "読みの整形はカタカナ以外を除き、ひらがな・半角カナ・合成濁点をカタカナへ畳む" do
    extractor = ReadingExtractor.new

    assert_equal "シャーロットリンリン", normalize(extractor, "シャーロット・リンリン")
    assert_equal "ロングロングロング", normalize(extractor, "ロング＆ロング ロング")
    assert_equal "プニプニ", normalize(extractor, "ぷにぷに")
    assert_equal "シャーロット", normalize(extractor, "ｼｬｰﾛｯﾄ")
    assert_equal "ヴァイオリン", normalize(extractor, "ゔぁいおりん")
    assert_nil normalize(extractor, "Dr.")
    assert_nil normalize(extractor, "")

    # 読みの整形は半角カナ・合成濁点・ゔ を畳み、ゕ・ゖ を落とす
    # かなの畳み込み(T0-18): NFKC で畳み、ひらがなは「ぁ-んゔ」の範囲だけカタカナにする。ゕ・ゖ は落ちる。
    assert_equal "ガギガヴ", normalize(ReadingExtractor.new, KANA_FOLD_SAMPLE)
  end

  private

  def normalize(extractor, line) = extractor.normalize(line)
end
