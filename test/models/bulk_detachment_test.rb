require "test_helper"

# 単語の修正の一覧で選んだ語から、指定した値をまとめて外す(Issue 108)。
# 規則は「指定した値が付いている語義から、その値だけを外す」。
class BulkDetachmentTest < ActiveSupport::TestCase
  setup do
    @murder = words(:abc_murder)        # 語義 murder: 小説・書籍名・名詞、特徴 連濁(殺人)・重箱読み(事件)
    @murder_sense = word_senses(:murder)
    @curry = words(:curry)
  end

  test "特徴は、該当部分を添えるとその該当部分のものだけを外し、特徴の数を焼き直す" do
    result = BulkDetachment.new(word_ids: [ @murder.id, @curry.id ],
                                linguistic_feature_id: linguistic_features(:rendaku).id, feature_target: " 殺人 ").apply

    assert_equal [ 1, 1 ], [ result.words, result.removed ]
    assert_equal [ word_sense_features(:murder_jubako).id ], @murder_sense.word_sense_features.ids
    assert_equal 1, @murder.reload.feature_count
  end

  test "該当部分が空なら、その特徴をすべて外す。選んでいない語と、ほかの特徴には触れない" do
    other = Word.create!(surface: "殺人の語").word_senses.create!(reading: "さつじんのご")
    other_feature = other.word_sense_features.create!(linguistic_feature: linguistic_features(:jubako),
                                                      target: "殺人", target_reading: "さつじん")
    second_jubako = @murder_sense.word_sense_features.create!(linguistic_feature: linguistic_features(:jubako),
                                                              target: "殺人", target_reading: "さつじん")

    result = BulkDetachment.new(word_ids: [ @murder.id ], linguistic_feature_id: linguistic_features(:jubako).id).apply

    assert_equal [ 1, 2 ], [ result.words, result.removed ]
    assert_equal [ word_sense_features(:murder_rendaku).id ], @murder_sense.word_sense_features.ids
    assert WordSenseFeature.exists?(other_feature.id), "選んでいない語の特徴を外した"
    assert_not WordSenseFeature.exists?(second_jubako.id)
  end

  test "エンティティ・品詞・語種は、指定した値が付いた語義からだけ外し、複数語義の語にも効く" do
    @murder_sense.update!(word_origins: [ word_origins(:kango), word_origins(:eigo) ])
    second = @murder.word_senses.create!(reading: "えーびーしーさつじんじけん", entity_type: entity_types(:person_name),
                                         part_of_speech: parts_of_speech(:noun))

    result = BulkDetachment.new(word_ids: [ @murder.id ], entity_type_id: entity_types(:book_title).id,
                                part_of_speech_id: parts_of_speech(:noun).id,
                                word_origin_ids: [ "", word_origins(:eigo).id.to_s ]).apply

    # 書籍名(1) + 名詞(2 語義) + 英語(1)
    assert_equal [ 1, 4 ], [ result.words, result.removed ]
    @murder_sense.reload
    assert_nil @murder_sense.entity_type_id
    assert_nil @murder_sense.part_of_speech_id
    assert_equal [ word_origins(:kango).id ], @murder_sense.word_origin_ids
    second.reload
    assert_equal entity_types(:person_name).id, second.entity_type_id, "違う値まで外した"
    assert_nil second.part_of_speech_id
  end

  test "ジャンルは、指定したジャンルと配下が付いた語義から外す" do
    result = BulkDetachment.new(word_ids: [ @murder.id, @curry.id ], genre_id: genres(:large_literature).id).apply

    assert_equal 1, result.removed
    assert_nil @murder_sense.reload.genre_id
  end

  test "外しても注釈状態と収録日は変えず、語の更新日時を動かす" do
    annotated_at = @murder.annotated_at
    travel_to 1.day.from_now do
      BulkDetachment.new(word_ids: [ @murder.id ], linguistic_feature_id: linguistic_features(:rendaku).id).apply
      @murder.reload
      assert @murder.annotation_done?
      assert_equal annotated_at, @murder.annotated_at
      assert_in_delta Time.current, @murder.updated_at, 1.second
    end
  end

  test "外すものが無ければ何も変えずに 0 件を返す" do
    result = BulkDetachment.new(word_ids: [ @curry.id ], linguistic_feature_id: linguistic_features(:rendaku).id).apply
    assert_equal [ 0, 0 ], [ result.words, result.removed ]
  end

  test "途中で失敗したら全体を巻き戻す" do
    failing = ->(*) { raise ActiveRecord::RecordInvalid, WordSense.new }
    assert_raises(ActiveRecord::RecordInvalid) do
      stub_method(WordSenseOrigin, :where, failing) do
        BulkDetachment.new(word_ids: [ @murder.id ], linguistic_feature_id: linguistic_features(:rendaku).id,
                           word_origin_ids: [ word_origins(:kango).id ]).apply
      end
    end
    assert_equal 2, @murder_sense.word_sense_features.count, "特徴を外したまま残った"
  end

  test "語・外すものが無いか、該当部分だけで特徴を選んでいないとバリデーションエラー" do
    assert_includes BulkDetachment.new(word_ids: [], genre_id: genres(:small_novel).id).tap(&:valid?)
                                  .errors.full_messages.join, "外す語"
    assert_includes BulkDetachment.new(word_ids: [ @murder.id ], word_origin_ids: [ "" ]).tap(&:valid?)
                                  .errors.full_messages.join, "外すもの"
    assert_includes BulkDetachment.new(word_ids: [ @murder.id ], feature_target: "殺人").tap(&:valid?)
                                  .errors.full_messages.join, "特徴も選んで"
  end
end
