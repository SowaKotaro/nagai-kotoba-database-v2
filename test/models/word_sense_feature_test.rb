require "test_helper"

class WordSenseFeatureTest < ActiveSupport::TestCase
  # 有効な属性一式(word_sense murder = ABC殺人事件 / さつじんじけん の一部)。
  def valid_attributes(**overrides)
    { word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku),
      target: "事件", target_reading: "じけん" }.merge(overrides)
  end

  test "該当部分は必須で、表層形・読みに含まれ、出現位置は 0 以上(未指定なら最初の出現位置)" do
    assert WordSenseFeature.new(valid_attributes).valid?

    # target が空だと無効
    wsf = WordSenseFeature.new(valid_attributes(target: ""))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target, :blank)

    # target_reading が空だと無効
    wsf = WordSenseFeature.new(valid_attributes(target_reading: ""))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target_reading, :blank)

    # target が表層形に含まれないと無効
    wsf = WordSenseFeature.new(valid_attributes(target: "犬"))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target, :not_in_surface)

    # target_reading が読みに含まれないと無効
    wsf = WordSenseFeature.new(valid_attributes(target_reading: "いぬ"))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target_reading, :not_in_reading)

    # target_start が負だと無効
    wsf = WordSenseFeature.new(valid_attributes(target: "殺人", target_reading: "さつじん", target_start: -1))
    assert_not wsf.valid?
    assert wsf.errors.added?(:target_start, :greater_than_or_equal_to, value: -1, count: 0)

    # target_start 未指定なら最初の出現位置に補完される
    # ABC殺人事件 の 殺人 は先頭から3文字目(0始まり)。
    wsf = WordSenseFeature.new(valid_attributes(target: "殺人", target_reading: "さつじん", target_start: nil))
    wsf.valid?
    assert_equal 3, wsf.target_start
  end

  test "一意の範囲は 語義 × 特徴 × 該当部分 × 出現位置" do
    dup = WordSenseFeature.new(valid_attributes(target: "殺人", target_reading: "さつじん"))
    assert_not dup.valid?
    assert dup.errors.of_kind?(:target, :taken)

    # 同じ語義×特徴でも該当部分が違えば有効
    # murder には既に 連濁:殺人 がある。別の該当部分 事件 なら追加できる。
    assert WordSenseFeature.new(valid_attributes(target: "事件", target_reading: "じけん")).valid?

    # 別の語義には同じ特徴を付けられる
    wsf = WordSenseFeature.new(word_sense: word_senses(:curry), linguistic_feature: linguistic_features(:rendaku),
                              target: "カレー", target_reading: "カレー")
    assert wsf.valid?

    # 同じ語の別の語義になら、同じ特徴・同じ該当部分・同じ出現位置でも付けられる
    # 一意の範囲(語義 × 特徴 × 該当部分 × 出現位置)に語義が入っていることを、同じ該当部分で確かめる。
    other_sense = words(:abc_murder).word_senses.create!(reading: "さつじんじけん")
    wsf = WordSenseFeature.new(word_sense: other_sense, linguistic_feature: linguistic_features(:rendaku),
                              target: "殺人", target_reading: "さつじん", target_start: 3)
    assert wsf.valid?

    duplicate = WordSenseFeature.new(word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku),
                                     target: "殺人", target_reading: "さつじん", target_start: 3)
    assert_not duplicate.valid?, "同じ語義なら重複になる(fixture の murder_rendaku と同じ四つ組)"

    # 同じ該当部分でも出現位置が違えば複数登録できる
    word = Word.create!(surface: "びしょびしょびしょ")
    sense = word.word_senses.create!(reading: "ビショビショビショ")
    feature = linguistic_features(:rendaku)
    assert sense.word_sense_features.create!(linguistic_feature: feature, target: "びしょ",
                                             target_reading: "ビショ", target_start: 0)
    second = sense.word_sense_features.new(linguistic_feature: feature, target: "びしょ",
                                           target_reading: "ビショ", target_start: 6)
    assert second.valid?, "別の出現位置なら同じ該当部分でも追加できる"
    dup = sense.word_sense_features.new(linguistic_feature: feature, target: "びしょ",
                                        target_reading: "ビショ", target_start: 0)
    assert_not dup.valid?, "同じ出現位置の重複は不可"
    assert dup.errors.of_kind?(:target, :taken)
  end

  # 単語の修正の絞り込みと「まとめて外す」が共有する行の選び方(Issue 108)。
  test "matching は特徴と該当部分(文字どおりの完全一致)で行を選び、省いた条件は問わない" do
    rendaku = word_sense_features(:murder_rendaku)
    jubako = word_sense_features(:murder_jubako)
    voiced = Word.create!(surface: "ヴウウの語").word_senses.create!(reading: "ヴウウノゴ")
                 .word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku), target: "ヴウ", target_reading: "ヴウ")
    plain = Word.create!(surface: "ウウウの語").word_senses.create!(reading: "ウウウノゴ")
                .word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku), target: "ウウ", target_reading: "ウウ")

    assert_equal [ rendaku, voiced, plain ].map(&:id).sort,
                 WordSenseFeature.matching(linguistic_feature_id: linguistic_features(:rendaku).id).ids.sort
    assert_equal [ jubako.id ], WordSenseFeature.matching(target: "事件").ids
    # 清濁を区別する(target の照合順序 ai_ci なら「ヴウ」も一致してしまう)。部分一致もしない
    assert_equal [ plain.id ], WordSenseFeature.matching(target: "ウウ").ids
    assert_empty WordSenseFeature.matching(target: "殺")
    assert_empty WordSenseFeature.matching(linguistic_feature_id: linguistic_features(:jubako).id, target: "殺人")
    assert_equal WordSenseFeature.count, WordSenseFeature.matching(linguistic_feature_id: "", target: nil).count
  end

  test "feature_ids_by_word は語ごとに、どの語義に付いた特徴の id も重ねずに返し、特徴の無い語はキーを持たない" do
    murder = words(:abc_murder)
    murder.word_senses.create!(reading: "えーびーしーさつじんじけん")
          .word_sense_features.create!(linguistic_feature: linguistic_features(:rendaku), target: "殺人", target_reading: "さつじん")

    result = WordSenseFeature.feature_ids_by_word([ murder.id, words(:curry).id ])
    assert_equal [ murder.id ], result.keys
    assert_equal [ linguistic_features(:rendaku).id, linguistic_features(:jubako).id ].sort, result[murder.id].sort
  end

  # --- 同一文字列が繰り返す語(target_start による出現箇所の区別) ---
end
