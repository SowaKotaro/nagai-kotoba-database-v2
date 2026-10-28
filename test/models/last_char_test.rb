require "test_helper"

class LastCharTest < ActiveSupport::TestCase
  test "末尾の長音を飛ばした最後の1文字(長音だけ・空なら nil)" do
    assert_equal "ら", LastChar.call("さくら")

    # 末尾が長音1つの場合、直前の長音以外の文字になる
    assert_equal "ガ", LastChar.call("ハンバーガー")

    # 末尾に長音が複数連続する場合も、直前の長音以外の文字になる
    assert_equal "カ", LastChar.call("スーパーカーーー")

    # 全体が長音のみの場合は nil
    assert_nil LastChar.call("ー")
    assert_nil LastChar.call("ーー")

    # 空文字・nil は nil
    assert_nil LastChar.call("")
    assert_nil LastChar.call(nil)
  end
end
