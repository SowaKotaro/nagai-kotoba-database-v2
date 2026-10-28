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

  test "表層形か読みが一致すれば完全一致、似ていれば候補、掠りもしなければ該当なし" do
    result = first_result(surface: words(:abc_murder).surface)

    assert_predicate result, :exact?
    assert_equal words(:abc_murder).id, result.matches.first.word_id

    # 読みが一致すれば表層形が違っても完全一致になる
    # 格納はひらがな、入力はカタカナでも畳んで同一視する(DB の as_ci と同じ扱い)。
    result = first_result(surface: "まったく別の表記", reading: "サツジンジケン")

    assert_predicate result, :exact?

    # 似ている表層形は候補として返る
    result = first_result(surface: "ABC殺人事故")

    assert_predicate result, :similar?
    assert_equal words(:abc_murder).surface, result.matches.first.surface
    assert_operator result.matches.first.similarity, :>=, Levenshtein::SIMILARITY_THRESHOLD

    # 読みが入力されていれば読み同士で似ているかを見る
    result = first_result(surface: "似ていない表記", reading: "サツジンジケソ")

    assert_predicate result, :similar?

    # 掠りもしない語は該当なしになる
    result = first_result(surface: "まったく関係のない長い言葉")

    assert_predicate result, :none?
    assert_empty result.matches
  end

  test "照合の対象と単位: 公開語だけ・空行は無視・語数に上限・語単位で1件・複数語をまとめて" do
    # fixtures の pending_haruhi は annotated_at が無く、公開面には出ていない。
    result = first_result(surface: words(:pending_haruhi).surface)

    assert_predicate result, :none?

    # 表層形が空の行は無視する
    results = check([ { surface: "", reading: "ヨミダケアル" }, { surface: "ある言葉" } ])

    assert_equal 1, results.size
    assert_equal "ある言葉", results.first.surface

    # 一度に照合する語数には上限がある
    queries = Array.new(WordRequestDuplicateCheck::MAX_QUERIES + 5) { |i| { surface: "言葉#{i}" } }

    assert_equal WordRequestDuplicateCheck::MAX_QUERIES, check(queries).size

    # 同じ語に複数の語義があっても候補は語単位で1件にまとまる
    word = words(:abc_murder)
    word.word_senses.create!(reading: "べつのよみ")

    result = first_result(surface: word.surface)
    assert_equal 1, result.matches.count { |match| match.word_id == word.id }

    # 複数語をまとめて判定できる
    results = check([ { surface: words(:abc_murder).surface }, { surface: "存在しない言葉" } ])

    assert_predicate results.first, :exact?
    assert_predicate results.second, :none?
  end

  # かなの畳み込み(T0-18): NFKC で半角カナ・合成濁点を畳み、ひらがな(ゔ・ゕ・ゖ を含む)をカタカナへ寄せる。
  test "fold は半角カナ・合成濁点を畳み、ゔ・ゕ・ゖ もカタカナへ寄せる" do
    assert_equal "ガギガヴヵヶ", WordRequestDuplicateCheck.fold(KANA_FOLD_SAMPLE)
  end
end
