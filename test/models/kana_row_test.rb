require "test_helper"

class KanaRowTest < ActiveSupport::TestCase
  test "清音はその行に写像される" do
    assert_equal "カ", KanaRow.row("カ")
    assert_equal "ワ", KanaRow.row("ヲ")
    assert_equal "ン", KanaRow.row("ン")
  end

  test "濁音・半濁音は清音の行に含める(しりとりの慣習)" do
    assert_equal "カ", KanaRow.row("ガ")
    assert_equal "ハ", KanaRow.row("パ")
    assert_equal "ア", KanaRow.row("ヴ")
  end

  test "小書きかなは大書きの行に含める" do
    assert_equal "タ", KanaRow.row("ッ")
    assert_equal "ヤ", KanaRow.row("ョ")
  end

  test "ひらがな・半角カナも同じ行に写像される" do
    assert_equal "サ", KanaRow.row("さ")
    assert_equal "カ", KanaRow.row("ｶ")
  end

  test "かな以外(記号・長音符・漢字)は行を持たない" do
    assert_nil KanaRow.row("ー")
    assert_nil KanaRow.row("漢")
    assert_nil KanaRow.row("A")
    assert_nil KanaRow.row(nil)
  end

  test "base は基本46字へ畳む(濁音・小書き・歴史的仮名)" do
    assert_equal "カ", KanaRow.base("ガ")
    assert_equal "ハ", KanaRow.base("ぱ")
    assert_equal "ツ", KanaRow.base("ッ")
    assert_equal "イ", KanaRow.base("ヰ")
    assert_equal "ウ", KanaRow.base("ヴ")
    assert_equal "ヲ", KanaRow.base("ヲ")
  end

  test "base は基本46字に載らない文字に nil を返す" do
    assert_nil KanaRow.base("ー")
    assert_nil KanaRow.base("漢")
  end

  test "基本46字はちょうど46字" do
    assert_equal 46, KanaRow::BASE_46.size
    assert_equal KanaRow::BASE_46.size, KanaRow::BASE_46.uniq.size
  end

  test "行の全メンバーが行の写像と一致する(表の自己整合)" do
    KanaRow::ROWS.each do |row, chars|
      chars.each { |char| assert_equal row, KanaRow.row(char) }
    end
  end
end
