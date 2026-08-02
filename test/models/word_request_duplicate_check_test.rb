require "test_helper"

# 収録リクエストの重複チェック(Issue 75)。
# 判定は管理側の一括登録と同じ Levenshtein・同じしきい値で、読みがあれば読み、無ければ表層形に当てる。
class WordRequestDuplicateCheckTest < ActiveSupport::TestCase
  def check(queries)
    WordRequestDuplicateCheck.new(queries).call
  end

  def first_result(surface:, reading: nil)
    check([ { surface: surface, reading: reading } ]).first
  end

  test "収録済みの表層形は完全一致になる" do
    result = first_result(surface: words(:abc_murder).surface)

    assert_predicate result, :exact?
    assert_equal words(:abc_murder).id, result.matches.first.word_id
  end

  test "読みが一致すれば表層形が違っても完全一致になる" do
    # 格納はひらがな、入力はカタカナでも畳んで同一視する(DB の as_ci と同じ扱い)。
    result = first_result(surface: "まったく別の表記", reading: "サツジンジケン")

    assert_predicate result, :exact?
  end

  test "似ている表層形は候補として返る" do
    result = first_result(surface: "ABC殺人事故")

    assert_predicate result, :similar?
    assert_equal words(:abc_murder).surface, result.matches.first.surface
    assert_operator result.matches.first.similarity, :>=, Levenshtein::SIMILARITY_THRESHOLD
  end

  test "読みが入力されていれば読み同士で似ているかを見る" do
    result = first_result(surface: "似ていない表記", reading: "サツジンジケソ")

    assert_predicate result, :similar?
  end

  test "掠りもしない語は該当なしになる" do
    result = first_result(surface: "まったく関係のない長い言葉")

    assert_predicate result, :none?
    assert_empty result.matches
  end

  test "未公開(未注釈)の語は照合の対象にしない" do
    # fixtures の pending_haruhi は annotated_at が無く、公開面には出ていない。
    result = first_result(surface: words(:pending_haruhi).surface)

    assert_predicate result, :none?
  end

  test "表層形が空の行は無視する" do
    results = check([ { surface: "", reading: "ヨミダケアル" }, { surface: "ある言葉" } ])

    assert_equal 1, results.size
    assert_equal "ある言葉", results.first.surface
  end

  test "一度に照合する語数には上限がある" do
    queries = Array.new(WordRequestDuplicateCheck::MAX_QUERIES + 5) { |i| { surface: "言葉#{i}" } }

    assert_equal WordRequestDuplicateCheck::MAX_QUERIES, check(queries).size
  end

  test "同じ語に複数の語義があっても候補は語単位で1件にまとまる" do
    word = words(:abc_murder)
    word.word_senses.create!(reading: "べつのよみ", rhythm_pattern: "betsunoyomi",
                             vowel_pattern: "euooi", mora_count: 6, last_char: "み")

    result = first_result(surface: word.surface)
    assert_equal 1, result.matches.count { |match| match.word_id == word.id }
  end

  test "複数語をまとめて判定できる" do
    results = check([ { surface: words(:abc_murder).surface }, { surface: "存在しない言葉" } ])

    assert_predicate results.first, :exact?
    assert_predicate results.second, :none?
  end
end
