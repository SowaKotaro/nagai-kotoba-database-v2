require "test_helper"

# 調査用データの書き出し(Issue 38)。対象語とマスタ一覧をスキル入力用の JSON にまとめる。
class AnnotationResearchExportTest < ActiveSupport::TestCase
  test "対象語(word_id・表層形・読み)とマスタ一覧を JSON にまとめる" do
    words = Word.unannotated.includes(:word_senses).order(:id)
    data = AnnotationResearchExport.new(words).as_json

    assert_equal "2", data["version"]

    haruhi = data["words"].find { |w| w["word_id"] == words(:pending_haruhi).id }
    assert_equal "涼宮ハルヒの憂鬱", haruhi["surface"]
    assert_equal "すずみやはるひのゆううつ", haruhi["reading"]

    # ジャンルは {大分類 => {中分類 => [小分類, ...]}} の木で渡す(省トークン)。
    assert_includes data["masters"]["genres"].fetch("文学").fetch("日本文学"), "小説"
    assert_includes data["masters"]["entity_types"], "書籍名"
    assert_includes data["masters"]["parts_of_speech"], "名詞"
    assert_includes data["masters"]["word_origins"], "和語"
    assert data["masters"].key?("linguistic_features")
  end

  test "木は3階層で、大分類の値は中分類のハッシュ・中分類の値は小分類名の配列になる" do
    data = AnnotationResearchExport.new(Word.unannotated.includes(:word_senses)).as_json

    data["masters"]["genres"].each do |large_name, mediums|
      assert_kind_of String, large_name
      assert_kind_of Hash, mediums
      mediums.each_value do |smalls|
        assert_kind_of Array, smalls
        smalls.each { |name| assert_kind_of String, name }
      end
    end
  end

  test "小分類がまだ1件も無い中分類も空配列で含める(寄せ先として渡す)" do
    WordSense.update_all(genre_id: nil) # 参照されていると小分類を消せない(restrict_with_error)
    Genre.small.destroy_all
    data = AnnotationResearchExport.new(Word.unannotated.includes(:word_senses)).as_json

    assert_equal [], data["masters"]["genres"].fetch("文学").fetch("日本文学")
  end
end
