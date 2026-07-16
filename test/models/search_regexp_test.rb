require "test_helper"

class SearchRegexpTest < ActiveSupport::TestCase
  test "空の入力は present? が偽でエラーも無い" do
    regexp = SearchRegexp.new("")
    assert_not regexp.present?
    assert_nil regexp.error
  end

  test "前後の空白は落とす" do
    assert_equal "^ア.*ン$", SearchRegexp.new("  ^ア.*ン$  ").source
  end

  test "読み用のパターンはひらがなをカタカナへ畳む" do
    assert_equal "^カレー$", SearchRegexp.new("^かれー$").for_reading
  end

  test "読み用のパターンでもメタ文字・英数字は変わらない" do
    assert_equal "(キョウ|トウ)[A-Z]{2}", SearchRegexp.new("(きょう|とう)[A-Z]{2}").for_reading
  end

  test "表層形用のパターンは入力のまま(漢字かな交じりを当てるため畳まない)" do
    assert_equal "風が.*吹い", SearchRegexp.new("風が.*吹い").for_surface
  end

  test "正しい正規表現はエラーにならない" do
    assert_nil SearchRegexp.new("^ア.*ン$").error
  end

  test "構文が壊れた正規表現は :syntax" do
    assert_equal :syntax, SearchRegexp.new("(ア").error
  end

  test "閉じていない文字クラスも :syntax" do
    assert_equal :syntax, SearchRegexp.new("[ア-").error
  end

  test "上限を超える長さは :too_long" do
    assert_equal :too_long, SearchRegexp.new("ア" * (SearchRegexp::MAX_LENGTH + 1)).error
  end

  test "上限ちょうどは許可する" do
    assert_nil SearchRegexp.new("ア" * SearchRegexp::MAX_LENGTH).error
  end

  test "長さの判定は構文チェックより先(長い壊れた式でも :too_long)" do
    assert_equal :too_long, SearchRegexp.new("(#{'ア' * SearchRegexp::MAX_LENGTH}").error
  end
end
