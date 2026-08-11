require "test_helper"

class FeatureResearchExportTest < ActiveSupport::TestCase
  setup do
    @japanese = word_origins(:nihongo)
  end

  # 公開済み・特徴0件・未調査 の語義を1件だけ用意する。
  def published_sense_without_features(surface: "調査対象の語", reading: "チョウサタイショウノゴ", japanese: true)
    word = Word.create!(surface: surface, annotated_at: Time.current)
    sense = word.word_senses.create!(reading: reading, meaning: "テスト用")
    sense.word_origins << @japanese if japanese
    sense
  end

  test "公開済みで特徴が付いていない語義を書き出す" do
    sense = published_sense_without_features
    json = JSON.parse(FeatureResearchExport.new([ sense ]).to_json)

    assert_equal "linguistic_features_only", json["task"]
    entry = json["senses"].first
    assert_equal sense.word_id, entry["word_id"]
    assert_equal sense.id, entry["sense_id"]
    assert_equal "調査対象の語", entry["surface"]
    assert_equal "チョウサタイショウノゴ", entry["reading"]
    assert_includes entry["word_origins"], "日本語"
  end

  test "意味やジャンルは書き出さない" do
    sense = published_sense_without_features
    entry = JSON.parse(FeatureResearchExport.new([ sense ]).to_json)["senses"].first

    assert_not entry.key?("meaning")
    assert_not entry.key?("genre_path")
    assert_not entry.key?("entity_type")
  end

  test "特徴マスタの一覧を添える" do
    json = JSON.parse(FeatureResearchExport.new([]).to_json)
    assert_equal LinguisticFeature.order(:id).pluck(:name), json["masters"]["linguistic_features"]
  end

  # --- 対象の抽出 ---

  test "未公開の語義は対象にしない" do
    word = Word.create!(surface: "未公開の語", annotated_at: nil)
    sense = word.word_senses.create!(reading: "ミコウカイノゴ")
    sense.word_origins << @japanese

    assert_not_includes FeatureResearchExport.target_senses(limit: 100), sense
  end

  test "既に特徴が付いている語義は対象にしない" do
    sense = published_sense_without_features
    sense.word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku),
                                      target: "調査", target_reading: "チョウサ")

    assert_not_includes FeatureResearchExport.target_senses(limit: 100), sense
  end

  test "「調査済みで該当なし」の語義は対象にしない" do
    sense = published_sense_without_features
    assert_includes FeatureResearchExport.target_senses(limit: 100), sense

    sense.update!(features_reviewed_at: Time.current)

    assert_not_includes FeatureResearchExport.target_senses(limit: 100), sense
  end

  test "既定では語種に日本語を含まない語義を対象にしない" do
    japanese_sense = published_sense_without_features(surface: "和語の語", reading: "ワゴノゴアイウエオ")
    foreign_sense = published_sense_without_features(surface: "外来の語", reading: "ガイライノゴアイウエオ",
                                                    japanese: false)
    foreign_sense.word_origins << word_origins(:eigo)

    targets = FeatureResearchExport.target_senses(limit: 100)
    assert_includes targets, japanese_sense
    assert_not_includes targets, foreign_sense

    # japanese_only: false なら両方入る
    all_targets = FeatureResearchExport.target_senses(limit: 100, japanese_only: false)
    assert_includes all_targets, japanese_sense
    assert_includes all_targets, foreign_sense
  end

  test "語ID範囲と件数で絞れる" do
    first = published_sense_without_features(surface: "範囲テストA", reading: "ハンイテストエイアイウ")
    second = published_sense_without_features(surface: "範囲テストB", reading: "ハンイテストビイアイウ")

    targets = FeatureResearchExport.target_senses(limit: 100, from_id: second.word_id)
    assert_not_includes targets, first
    assert_includes targets, second

    assert_equal 1, FeatureResearchExport.target_senses(limit: 1, from_id: first.word_id).size
  end
end
