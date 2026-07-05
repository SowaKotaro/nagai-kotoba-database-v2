require "test_helper"

class BulkWordRegistrationTest < ActiveSupport::TestCase
  test "テキスト未入力は無効" do
    assert_not BulkWordRegistration.new(text: "").valid?
    assert_not BulkWordRegistration.new(text: nil).valid?
  end

  test "複数行を表層形+読みで登録し、結果を集計する" do
    reg = BulkWordRegistration.new(text: "銀河鉄道の夜　ギンガテツドウノヨル\n活版印刷術　カッパンインサツジュツ")
    result = nil
    assert_difference [ "Word.count", "WordSense.count" ], 2 do
      result = reg.register
    end
    assert_equal 2, result.created
    assert_equal 0, result.skipped
    assert_empty result.errors
    assert_nil Word.find_by(surface: "銀河鉄道の夜").annotated_at
  end

  test "空行は飛ばす" do
    reg = BulkWordRegistration.new(text: "\n\n傘連判状　カラカサレンパンジョウ\n\n")
    assert_difference -> { Word.count }, 1 do
      assert_equal 1, reg.register.created
    end
  end

  test "半角空白/タブ/全角空白のいずれの区切りでも分けられる" do
    reg = BulkWordRegistration.new(text: "半角 ハンカク\nタブ\tタブ\n全角　ゼンカク")
    result = reg.register
    assert_equal 3, result.created
    assert_empty result.errors
  end

  test "表層形に半角空白を含む語は行末の空白で読みと分ける" do
    reg = BulkWordRegistration.new(text: "Dead by Daylight デッドバイデイライト")
    reg.register
    word = Word.find_by(surface: "Dead by Daylight")
    assert_not_nil word
    assert_equal "デッドバイデイライト", word.word_senses.sole.reading
  end

  test "読み欠落の行はエラーにして登録しない" do
    reg = BulkWordRegistration.new(text: "読みなし語")
    result = nil
    assert_no_difference -> { Word.count } do
      result = reg.register
    end
    assert_equal 0, result.created
    assert_equal 1, result.errors.size
  end

  test "既存の(表層形・読み)はスキップし、同じ表層形の新しい読みは追加する" do
    surface = words(:abc_murder).surface
    text = "#{surface}　#{word_senses(:murder).reading}\n#{surface}　ベツノヨミ"
    reg = BulkWordRegistration.new(text: text)
    result = nil
    assert_difference -> { WordSense.count }, 1 do
      result = reg.register
    end
    assert_equal 1, result.created
    assert_equal 1, result.skipped
  end
end
