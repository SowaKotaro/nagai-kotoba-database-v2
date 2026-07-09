require "test_helper"

class LastCharTest < ActiveSupport::TestCase
  test "末尾が長音でなければそのまま最後の1文字" do
    assert_equal "ら", LastChar.call("さくら")
  end

  test "末尾が長音1つの場合、直前の長音以外の文字になる" do
    assert_equal "ガ", LastChar.call("ハンバーガー")
  end

  test "末尾に長音が複数連続する場合も、直前の長音以外の文字になる" do
    assert_equal "カ", LastChar.call("スーパーカーーー")
  end

  test "全体が長音のみの場合は nil" do
    assert_nil LastChar.call("ー")
    assert_nil LastChar.call("ーー")
  end

  test "空文字・nil は nil" do
    assert_nil LastChar.call("")
    assert_nil LastChar.call(nil)
  end
end
