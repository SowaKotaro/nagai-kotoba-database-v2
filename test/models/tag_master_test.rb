require "test_helper"

# タグとして扱う単純マスタ(エンティティタイプ / 品詞 / 語種 / 言語学的特徴)に共通の振る舞い。
# 4モデルとも name の検証と TagMaster(使用件数・削除可否・統合)を共有するので、ここでまとめて確かめる。
# 階層を持つ Genre は同じ IF を独自に実装しているため GenreTest で扱う。
class TagMasterTest < ActiveSupport::TestCase
  # マスタごとに、語義に付いている(使用中の)タグと付いていないタグ。
  def masters
    @masters ||= {
      EntityType => { used: entity_types(:book_title), unused: entity_types(:person_name) },
      PartOfSpeech => { used: parts_of_speech(:noun), unused: parts_of_speech(:verb) },
      WordOrigin => { used: word_origins(:kango), unused: word_origins(:wago) },
      LinguisticFeature => { used: linguistic_features(:rendaku), unused: LinguisticFeature.create!(name: "湯桶読み") }
    }
  end

  test "name は必須で一意" do
    masters.each do |model, tags|
      blank = model.new(name: "")
      assert_not blank.valid?, "#{model} が空の name を許している"
      assert blank.errors.added?(:name, :blank)

      duplicate = model.new(name: tags[:used].name)
      assert_not duplicate.valid?, "#{model} が同名を許している"
      assert duplicate.errors.added?(:name, :taken, value: tags[:used].name)

      assert model.new(name: "まだ無い名前").valid?, "#{model} が新しい名前を受け付けない"
    end
  end

  test "usage_count は付与している語義数で、未使用のタグだけ deletable? になる" do
    expected_usage = { EntityType => 1, PartOfSpeech => 2, WordOrigin => 1, LinguisticFeature => 1 }

    masters.each do |model, tags|
      assert_equal expected_usage[model], tags[:used].usage_count, model.name
      assert_equal 0, tags[:unused].usage_count, model.name
      assert_not tags[:used].deletable?, model.name
      assert tags[:unused].deletable?, model.name
    end
  end

  test "語義に付いているタグは destroy できず、付いていなければ消せる" do
    masters.each do |model, tags|
      assert_not tags[:used].destroy, "#{model} の使用中タグが消えてしまった"
      assert model.exists?(tags[:used].id)
      assert tags[:used].errors.of_kind?(:base, :"restrict_dependent_destroy.has_many")

      assert tags[:unused].destroy, "#{model} の未使用タグが消せない"
    end
  end

  test "merge_into! は語義の参照を統合先へ付け替え、統合元を消す" do
    # 語義が FK で持つマスタ
    entity_types(:book_title).merge_into!(entity_types(:person_name))
    assert_not EntityType.exists?(entity_types(:book_title).id)
    assert_equal entity_types(:person_name), word_senses(:murder).reload.entity_type

    parts_of_speech(:noun).merge_into!(parts_of_speech(:verb))
    assert_not PartOfSpeech.exists?(parts_of_speech(:noun).id)
    assert_equal parts_of_speech(:verb), word_senses(:murder).reload.part_of_speech
    assert_equal parts_of_speech(:verb), word_senses(:curry).reload.part_of_speech

    # 中間表で持つマスタは、中間表の行を付け替える
    word_origins(:eigo).merge_into!(word_origins(:wago))
    assert_not WordOrigin.exists?(word_origins(:eigo).id)
    assert_includes word_senses(:curry).reload.word_origins, word_origins(:wago)

    # murder の 重箱読み:事件 が 連濁:事件 になる(元の 連濁:殺人 とは該当部分が違うので両立する)
    linguistic_features(:jubako).merge_into!(linguistic_features(:rendaku))
    assert_not LinguisticFeature.exists?(linguistic_features(:jubako).id)
    assert WordSenseFeature.exists?(
      word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku), target: "事件"
    )
  end

  test "中間表の付け替えは、統合先に同じ行が既にあれば重複を作らない" do
    # murder は漢語を持つ。和語も付けてから漢語→和語へ統合すると、和語の行は1つにまとまる
    WordSenseOrigin.create!(word_sense: word_senses(:murder), word_origin: word_origins(:wago))
    word_origins(:kango).merge_into!(word_origins(:wago))
    assert_equal 1, WordSenseOrigin.where(word_sense: word_senses(:murder), word_origin: word_origins(:wago)).count

    # murder の 重箱読み:事件(位置5) と同じ該当部分の 連濁 を足してから統合すると、統合先で衝突する
    WordSenseFeature.create!(
      word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku),
      target: "事件", target_reading: "じけん", target_start: 5
    )
    linguistic_features(:jubako).merge_into!(linguistic_features(:rendaku))
    assert_equal 1, WordSenseFeature.where(
      word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku), target: "事件", target_start: 5
    ).count
  end

  test "merge_into! は同じタグ・種類の違うタグへの統合を拒否する" do
    tag = entity_types(:person_name)
    assert_raises(ArgumentError) { tag.merge_into!(tag) }
    assert_raises(ArgumentError) { tag.merge_into!(parts_of_speech(:noun)) }
  end
end
