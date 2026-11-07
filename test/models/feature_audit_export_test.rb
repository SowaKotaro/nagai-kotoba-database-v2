require "test_helper"

# 言語学的特徴の点検用データの書き出し(Issue 109)。
class FeatureAuditExportTest < ActiveSupport::TestCase
  test "公開済みの語を、語義ごとの読み・語種・いま付いている特徴とともに書き出す" do
    word = create_published_word(surface: "手紙の書き方", reading: "テガミノカキカタ")
    sense = word.word_senses.first
    sense.word_origins << word_origins(:nihongo)
    sense.word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku), target: "手紙", target_reading: "テガミ")

    json = JSON.parse(FeatureAuditExport.new([ word.reload ], feature_names: [ "連濁" ]).to_json)

    # 外に出る形はキーの集合ごと固定する(スキルの文書 word-feature-audit が読む)
    assert_equal %w[version task features_to_check words masters], json.keys
    assert_equal "linguistic_features_audit", json["task"]
    assert_equal [ "連濁" ], json["features_to_check"]
    entry = json["words"].first
    assert_equal %w[word_id surface senses], entry.keys
    assert_equal [ word.id, "手紙の書き方" ], [ entry["word_id"], entry["surface"] ]
    sense_entry = entry["senses"].first
    assert_equal %w[sense_id reading word_origins linguistic_features], sense_entry.keys
    assert_equal [ sense.id, "テガミノカキカタ", [ "日本語" ] ],
                 [ sense_entry["sense_id"], sense_entry["reading"], sense_entry["word_origins"] ]
    assert_equal [ { "name" => "連濁", "target" => "手紙", "target_reading" => "テガミ" } ], sense_entry["linguistic_features"]
    assert_includes json["masters"]["linguistic_features"], "連濁"
  end

  test "点検する特徴はマスタにある名前だけを残し、空なら全特徴を点検する(空の配列)" do
    assert_equal [ "連濁" ], FeatureAuditExport.new([], feature_names: [ "連濁", "無い特徴", "連濁" ]).feature_names
    assert_equal [], FeatureAuditExport.new([]).feature_names
  end

  test "対象は公開済みの語だけで、特徴があっても書き出し、語ID範囲と件数で絞れる" do
    first = create_published_word(surface: "一つ目の語", reading: "ヒトツメノゴ")
    second = create_published_word(surface: "二つ目の語", reading: "フタツメノゴ")
    second.word_senses.first.word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku),
                                                         target: "二つ", target_reading: "フタツ")
    unpublished = Word.create!(surface: "未公開の語")

    targets = FeatureAuditExport.target_words(limit: 3000)
    assert_includes targets, first
    assert_includes targets, second
    assert_not_includes targets, unpublished

    assert_equal [ second ], FeatureAuditExport.target_words(limit: 3000, from_id: second.id, to_id: second.id).to_a
    assert_equal 1, FeatureAuditExport.target_words(limit: 1).size
  end
end
