require "test_helper"

class WordTest < ActiveSupport::TestCase
  test "surface は必須で一意(かなの種類・小書きは同一視し、清濁は区別する)" do
    word = Word.new(surface: "")
    assert_not word.valid?
    assert word.errors.added?(:surface, :blank)

    # surface は一意
    dup = Word.new(surface: words(:abc_murder).surface)
    assert_not dup.valid?
    assert dup.errors.added?(:surface, :taken, value: words(:abc_murder).surface)

    # surface の一意性は、かなの種類・小書きを同一視し、清濁は区別する
    # 一意性は DB の照合順序(words.surface は utf8mb4_0900_as_ci)で判定される。
    # かなの種類・小書きの違いは同じ語とみなし、清濁の違いは別の語とみなす(docs/data-model.md §6)。
    Word.create!(surface: "シャーロット")

    assert_not Word.new(surface: "しゃーろっと").valid?, "ひらがな⇔カタカナは同じ語"
    assert_not Word.new(surface: "シヤーロット").valid?, "小書き⇔並字は同じ語"
    assert Word.new(surface: "ジャーロット").valid?, "清濁が違えば別の語"
  end

  test "保存時に surface の改行を除き、char_type_pattern を surface から作り直す" do
    word = Word.create!(surface: "令和6年")
    assert_equal "漢漢1漢", word.char_type_pattern

    # surface を変更すると char_type_pattern も追従する
    word = Word.create!(surface: "カレー")
    assert_equal "アアア", word.char_type_pattern

    word.update!(surface: "ABC")
    assert_equal "AAA", word.char_type_pattern

    # char_type_pattern に手入力しても surface から上書きされる
    word = Word.create!(surface: "犬", char_type_pattern: "でたらめ")
    assert_equal "漢", word.char_type_pattern

    # surface に混入した改行は保存時に除去される(内部の空白は残す)
    word = Word.create!(surface: "Dead by\r\nDaylight\n")
    assert_equal "Dead by Daylight", word.surface
  end

  test "公開状態(未対応/保留/完了)と annotated / unannotated のスコープ" do
    assert_includes Word.annotated, words(:abc_murder)
    assert_not_includes Word.annotated, words(:pending_haruhi)
    assert_includes Word.unannotated, words(:pending_haruhi)
    assert_not_includes Word.unannotated, words(:abc_murder)
    # 保留も annotated_at なしなので unannotated(未公開)に含まれる
    assert_includes Word.unannotated, words(:on_hold_word)

    # annotation_status は未対応/保留/完了の3状態
    assert words(:pending_haruhi).annotation_pending?
    assert words(:on_hold_word).annotation_on_hold?
    assert words(:abc_murder).annotation_done?

    assert_includes Word.annotation_pending, words(:pending_haruhi)
    assert_includes Word.annotation_on_hold, words(:on_hold_word)
    assert_includes Word.annotation_done, words(:abc_murder)
    # コンソールのキュー(未対応)には保留・完了は出ない
    assert_not_includes Word.annotation_pending, words(:on_hold_word)
    assert_not_includes Word.annotation_pending, words(:abc_murder)
  end

  test "mark_annotated / mark_on_hold は状態と収録日(annotated_at)を揃え、見直しでは収録日を動かさない" do
    word = words(:pending_haruhi)
    word.mark_annotated
    assert_not_nil word.annotated_at
    assert word.annotation_done?

    # mark_annotated は既にある annotated_at を書き換えない
    # annotated_at は収録日(公開日)として公開面に出るので、見直しのたびに動いてはいけない。
    word = words(:abc_murder)
    first_time = word.annotated_at
    travel_to 1.week.from_now do
      word.mark_annotated
      assert_equal first_time, word.annotated_at
    end

    # 保留を挟むと mark_annotated が新しい annotated_at を立てる
    # 保留でいったん未公開に戻した語は、次に完了した時刻が改めて収録日になる。
    word = words(:abc_murder)
    word.mark_on_hold
    travel_to 1.week.from_now do
      word.mark_annotated
      assert_equal Time.current.to_i, word.annotated_at.to_i
    end

    # mark_on_hold は状態を保留にし annotated_at を落とす
    word = words(:pending_haruhi)
    word.mark_on_hold
    assert word.annotation_on_hold?
    assert_nil word.annotated_at
  end

  # 代表の語義と語義の並びは id(登録順)で決め、読みの長さや読み込みの順には左右されない。
  test "primary_sense・featured_on・annotated_this_month" do
    word = Word.create!(surface: "語義の順序の見本")
    first = word.word_senses.create!(reading: "ミジカイヨミ")
    second = word.word_senses.create!(reading: "トテモナガイニバンメノヨミ")
    third = word.word_senses.create!(reading: "サンバンメノヨミ")

    loaded = Word.includes(:word_senses).find(word.id)
    assert_equal first, loaded.primary_sense
    assert_equal [ first, second, third ], loaded.ordered_senses

    empty = Word.create!(surface: "語義の無い見本")
    assert_nil empty.primary_sense
    assert_empty empty.ordered_senses

    # featured_on は日付と渡された語数で決まり、語数が 0 なら nil
    # 今日の一語は、公開語を id 順に並べた date.jd % count 番目。count は渡された数で、数え直さない。
    ordered = Word.annotated.order(:id).to_a # フィクスチャの公開語は 2 語
    date = Date.new(2026, 10, 1)
    date += 1 until date.jd.even?

    assert_equal ordered[0], Word.featured_on(date, count: 2)
    assert_equal ordered[1], Word.featured_on(date + 1, count: 2)
    # 渡された語数で割る(実際は 2 語でも、1 と渡せばいつも先頭)
    assert_equal ordered[0], Word.featured_on(date + 1, count: 1)
    assert_nil Word.featured_on(date, count: 0)

    # annotated_this_month は今月 annotated_at が立った公開語だけで、created_at は見ない
    # 「今月の新収録」(ホームと統計)の定義。月の境界は Time.zone で切り、created_at は見ない。
    travel_to Time.zone.local(2026, 10, 15, 12, 0) do
      # 公開日(annotated_at)の値そのものを試すので create_published_word は使わず、状態は「完了」で揃える
      first_moment = Word.create!(surface: "月初の語", annotated_at: Time.zone.local(2026, 10, 1, 0, 0, 0),
                                  annotation_status: :done, created_at: Time.zone.local(2026, 9, 1))
      last_moment = Word.create!(surface: "月末の語", annotated_at: Time.zone.local(2026, 10, 31, 23, 59, 59),
                                 annotation_status: :done)
      Word.create!(surface: "先月末の語", annotated_at: Time.zone.local(2026, 9, 30, 23, 59, 59),
                   annotation_status: :done, created_at: Time.zone.local(2026, 10, 2))
      Word.create!(surface: "今月作った未公開の語")

      assert_equal [ first_moment, last_moment ].sort_by(&:id), Word.annotated_this_month.order(:id).to_a
    end
  end
end
