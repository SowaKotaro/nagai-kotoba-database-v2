require "test_helper"

class SnsRotationTest < ActiveSupport::TestCase
  test "公開語を一巡するまで重ねず、巡の変わり目では直前の語を避け、本文が収まらない語と非公開の語は出さない" do
    create_published_word(surface: "長" * 70, reading: "ナ" * 70) # X の上限を超える
    published = Word.annotated.select { SnsPostText.fits?(Word.includes(:word_senses).find(it.id)) }.map(&:id)
    assert_equal [ words(:abc_murder).id, words(:curry).id ].sort, published.sort

    picks = 4.times.map do |hour|
      pick = SnsRotation.new(random: Random.new(hour)).call
      SnsSlot.create!(slot_at: Time.zone.local(2026, 11, 18, hour), word: pick.word, round: pick.round)
      pick
    end

    assert_equal [ 1, 1, 2, 2 ], picks.map(&:round)
    assert_equal published.sort, picks.first(2).map { it.word.id }.sort
    assert_equal published.sort, picks.last(2).map { it.word.id }.sort
    assert_not_equal picks[1].word, picks[2].word, "巡の変わり目で同じ語が続かない"
  end

  test "出せる語が無ければ nil" do
    Word.update_all(annotated_at: nil)
    assert_nil SnsRotation.new.call
  end
end
