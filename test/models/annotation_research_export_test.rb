require "test_helper"

# 調査用データの書き出し(Issue 38)。対象語とマスタ一覧をスキル入力用の JSON にまとめる。
class AnnotationResearchExportTest < ActiveSupport::TestCase
  test "対象語(word_id・表層形・読み)とマスタ一覧を JSON にまとめる" do
    words = Word.unannotated.includes(:word_senses).order(:id)
    data = AnnotationResearchExport.new(words).as_json

    assert_equal "1", data["version"]

    haruhi = data["words"].find { |w| w["word_id"] == words(:pending_haruhi).id }
    assert_equal "涼宮ハルヒの憂鬱", haruhi["surface"]
    assert_equal "すずみやはるひのゆううつ", haruhi["reading"]

    # ジャンルは大→中→小のパスで渡す
    assert_includes data["masters"]["genres"], %w[文学 日本文学 小説]
    assert_includes data["masters"]["entity_types"], "書籍名"
    assert_includes data["masters"]["parts_of_speech"], "名詞"
    assert_includes data["masters"]["word_origins"], "和語"
    assert data["masters"].key?("linguistic_features")
  end
end
