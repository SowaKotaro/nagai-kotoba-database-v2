require "test_helper"

class SearchRegexpTest < ActiveSupport::TestCase
  test "入力の整え方: 前後の空白を落とし、読み用だけひらがなをカタカナへ寄せる" do
    regexp = SearchRegexp.new("")
    assert_not regexp.present?
    assert_nil regexp.error

    # 前後の空白は落とす
    assert_equal "^ア.*ン$", SearchRegexp.new("  ^ア.*ン$  ").source

    # 読み用のパターンはひらがなをカタカナへ畳む
    assert_equal "^カレー$", SearchRegexp.new("^かれー$").for_reading

    # 読み用のパターンでもメタ文字・英数字は変わらない
    assert_equal "(キョウ|トウ)[A-Z]{2}", SearchRegexp.new("(きょう|とう)[A-Z]{2}").for_reading

    # 表層形用のパターンは入力のまま(漢字かな交じりを当てるため畳まない)
    assert_equal "風が.*吹い", SearchRegexp.new("風が.*吹い").for_surface

    # for_reading は半角カナと合成濁点を畳まず、ひらがなだけをカタカナへ寄せる
    # かなの畳み込み(T0-18): NFKC をかけないので、半角カナと合成濁点は残り、ひらがな部分だけカタカナになる。
    expected = [ 0xFF76, 0xFF9E, 0xFF77, 0xFF9E, 0x30AB, 0x3099, 0x30F4, 0x30F5, 0x30F6 ].pack("U*")
    assert_equal expected, SearchRegexp.new(KANA_FOLD_SAMPLE).for_reading
  end

  test "エラー: 長さの上限を先に見て、構文の壊れた式は :syntax(判定は式ごとに覚える)" do
    assert_nil SearchRegexp.new("^ア.*ン$").error

    # 構文が壊れた正規表現は :syntax
    assert_equal :syntax, SearchRegexp.new("(ア").error

    # 閉じていない文字クラスも :syntax
    assert_equal :syntax, SearchRegexp.new("[ア-").error

    # 上限を超える長さは :too_long
    assert_equal :too_long, SearchRegexp.new("ア" * (SearchRegexp::MAX_LENGTH + 1)).error

    # 上限ちょうどは許可する
    assert_nil SearchRegexp.new("ア" * SearchRegexp::MAX_LENGTH).error

    # 長さの判定は構文チェックより先(長い壊れた式でも :too_long)
    assert_equal :too_long, SearchRegexp.new("(#{'ア' * SearchRegexp::MAX_LENGTH}").error

    # 同じ式の構文チェックは覚えておき、2回目は MySQL に問い合わせない(壊れた式も同じ)
    with_rails_cache do
      assert_nil SearchRegexp.new("^ア.*ン$").error
      assert_equal :syntax, SearchRegexp.new("(ア").error

      assert_no_queries do
        assert_nil SearchRegexp.new("^ア.*ン$").error
        assert_equal :syntax, SearchRegexp.new("(ア").error
      end
    end
  end
end
