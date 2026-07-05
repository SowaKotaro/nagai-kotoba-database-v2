require "test_helper"

class LevenshteinTest < ActiveSupport::TestCase
  test "同一文字列の距離は0" do
    assert_equal 0, Levenshtein.distance("さつじん", "さつじん")
  end

  test "片方が空なら距離はもう片方の文字数" do
    assert_equal 4, Levenshtein.distance("", "さつじん")
    assert_equal 4, Levenshtein.distance("さつじん", "")
    assert_equal 0, Levenshtein.distance("", "")
  end

  test "置換・挿入・削除の距離" do
    assert_equal 1, Levenshtein.distance("ねこ", "ねご")   # 置換1
    assert_equal 1, Levenshtein.distance("ねこ", "ねこん") # 挿入1
    assert_equal 1, Levenshtein.distance("ねこん", "ねこ") # 削除1
    assert_equal 3, Levenshtein.distance("kitten", "sitting")
  end

  test "類似度は 0.0〜1.0 で完全一致が1.0" do
    assert_in_delta 1.0, Levenshtein.similarity("さつじん", "さつじん"), 0.0001
    assert_in_delta 1.0, Levenshtein.similarity("", ""), 0.0001
  end

  test "類似度は長い方の文字数で正規化する" do
    # 距離1 / 長さ4(置換1) → 0.75
    assert_in_delta 0.75, Levenshtein.similarity("サツジン", "サツジソ"), 0.0001
    # 距離1 / 長さ3(挿入1) → 約0.667
    assert_in_delta(1.0 - (1.0 / 3), Levenshtein.similarity("ねこ", "ねこん"), 0.0001)
  end

  test "全く異なる読みの類似度は低い" do
    assert Levenshtein.similarity("さつじんじけん", "カレー") < 0.5
  end
end
