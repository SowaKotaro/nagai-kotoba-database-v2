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

    # ジャンルは中分類(大→中)と小分類(大→中→小)の両方のパスを渡す。
    # 中分類が無いとスキルが「寄せ先」を知らず、中分類ごと創作してしまう。
    assert_includes data["masters"]["genres"], %w[文学 日本文学 小説]
    assert_includes data["masters"]["genres"], %w[文学 日本文学]
    assert_includes data["masters"]["entity_types"], "書籍名"
    assert_includes data["masters"]["parts_of_speech"], "名詞"
    assert_includes data["masters"]["word_origins"], "和語"
    assert data["masters"].key?("linguistic_features")
  end

  test "大分類は単独のパスとしては渡さない(中分類パスの先頭に必ず現れるため)" do
    data = AnnotationResearchExport.new(Word.unannotated.includes(:word_senses)).as_json

    assert_not_includes data["masters"]["genres"], %w[文学]
    assert_equal [ 2, 3 ], data["masters"]["genres"].map(&:size).uniq.sort
  end

  test "小分類がまだ1件も無くても中分類までのパスを渡す" do
    WordSense.update_all(genre_id: nil) # 参照されていると小分類を消せない(restrict_with_error)
    Genre.small.destroy_all
    data = AnnotationResearchExport.new(Word.unannotated.includes(:word_senses)).as_json

    assert_includes data["masters"]["genres"], %w[文学 日本文学]
    assert_equal [ 2 ], data["masters"]["genres"].map(&:size).uniq
  end
end
