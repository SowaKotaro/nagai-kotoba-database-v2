require "test_helper"

class WordSenseSearchTest < ActiveSupport::TestCase
  # フィクスチャ:
  #   murder  … 読み さつじんじけん(7文字/先頭さ/末尾ん) 韻 satsujinjiken
  #             genre 小説, 品詞 名詞, entity 書籍名, 特徴 連濁/重箱読み
  #   curry   … 読み カレー(3文字/先頭カ/末尾ー) 韻 karee, 品詞 名詞, genre/entity/特徴 なし
  def ids(params)
    WordSenseSearch.new(params).results.pluck(:id).sort
  end

  test "条件なしなら全語義を返す" do
    assert_equal WordSense.pluck(:id).sort, ids({})
  end

  # --- キーワード(表層形・読みの部分一致) ---
  test "キーワードは表層形の部分一致で絞れる" do
    assert_equal [ word_senses(:murder).id ], ids(q: "殺人")
  end

  test "キーワードは読みの部分一致でも絞れる" do
    assert_equal [ word_senses(:murder).id ], ids(q: "さつじん")
  end

  test "キーワードの LIKE ワイルドカードはエスケープされる" do
    assert_equal [], ids(q: "%殺人%")
  end

  test "読みの文字数の下限で絞れる" do
    result = ids(reading_length_min: "5")
    assert_includes result, word_senses(:murder).id
    assert_not_includes result, word_senses(:curry).id
  end

  test "読みの文字数の上限で絞れる" do
    result = ids(reading_length_max: "3")
    assert_includes result, word_senses(:curry).id
    assert_not_includes result, word_senses(:murder).id
  end

  test "先頭文字で絞れる" do
    assert_equal [ word_senses(:murder).id ], ids(first_char: "さ")
  end

  test "末尾文字で絞れる" do
    assert_equal [ word_senses(:curry).id ], ids(last_char: "ー")
  end

  test "韻の部分一致で絞れる" do
    assert_equal [ word_senses(:murder).id ], ids(rhythm_pattern: "tsuji")
  end

  test "文字タイプ列の完全一致で絞れる(words と join)" do
    pattern = words(:abc_murder).char_type_pattern
    assert_equal [ word_senses(:murder).id ], ids(char_type_pattern: pattern)
  end

  test "品詞で絞れる" do
    result = ids(part_of_speech_id: parts_of_speech(:noun).id)
    assert_includes result, word_senses(:murder).id
    assert_includes result, word_senses(:curry).id
  end

  test "エンティティタイプで絞れる" do
    assert_equal [ word_senses(:murder).id ], ids(entity_type_id: entity_types(:book_title).id)
  end

  test "言語学的特徴で絞れる" do
    assert_equal [ word_senses(:murder).id ], ids(linguistic_feature_id: linguistic_features(:rendaku).id)
  end

  test "ジャンルは大分類を選ぶと配下の小分類で絞れる" do
    # 文学(大) を選ぶと 小説(小) を持つ murder が該当する。
    assert_equal [ word_senses(:murder).id ], ids(genre_id: genres(:large_literature).id)
  end

  test "ジャンルは小分類を直接指定しても絞れる" do
    assert_equal [ word_senses(:murder).id ], ids(genre_id: genres(:small_novel).id)
  end

  test "複数条件は AND で積み重なる" do
    both = ids(part_of_speech_id: parts_of_speech(:noun).id, first_char: "カ")
    assert_equal [ word_senses(:curry).id ], both
  end

  test "0 や不正な文字数は無視する" do
    assert_equal WordSense.pluck(:id).sort, ids(reading_length_min: "0", reading_length_max: "abc")
  end
end
