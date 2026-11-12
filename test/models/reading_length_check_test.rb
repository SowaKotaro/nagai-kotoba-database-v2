require "test_helper"

class ReadingLengthCheckTest < ActiveSupport::TestCase
  test "スキルの読みを正規化して数え、MeCab と基準の境界をまたぐときだけ要確認にする" do
    # [スキルの読み, MeCab の読み, 判定, 正規化した読み, 文字数]
    [
      [ "ギョウムジョウオウリョウザイ", nil, :ok, "ギョウムジョウオウリョウザイ", 14 ],
      [ "ムペンバコウカ", nil, :short, "ムペンバコウカ", 7 ],
      # 中黒・空白は数えず、ひらがなはカタカナに寄せる(ReadingExtractor#normalize と同じ)
      [ "ふぁいなんしゃる・ぷらんなー", nil, :ok, "ファイナンシャルプランナー", 13 ],
      # ちょうど基準値は通す
      [ "アイウエオカキクケコ", nil, :ok, "アイウエオカキクケコ", 10 ],
      [ "アイウエオカキクケ", nil, :short, "アイウエオカキクケ", 9 ],
      # MeCab と境界をまたぐと要確認、どちらも同じ側なら MeCab は判定を変えない
      [ "アイウエオカキクケコ", "アイウエオ", :uncertain, "アイウエオカキクケコ", 10 ],
      [ "アイウエオカキクケコ", "アイウエオカキクケコサシ", :ok, "アイウエオカキクケコ", 10 ],
      [ "・", nil, :missing, nil, nil ],
      [ nil, "アイウエオカキクケコ", :missing, nil, nil ]
    ].each do |reading, mecab, verdict, normalized, length|
      check = ReadingLengthCheck.call(reading, mecab)
      assert_equal [ verdict, normalized, length ], [ check.verdict, check.reading, check.length ], reading.inspect
      assert_equal verdict == :ok, check.ok?
    end
  end
end
