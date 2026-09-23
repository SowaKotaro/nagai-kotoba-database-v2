require "test_helper"

class WordCandidateDuplicateCheckTest < ActiveSupport::TestCase
  test "空白・中黒・記号・かなの種類・全角半角を無視して畳む(長音符と清濁は残す)" do
    assert_equal WordCandidateDuplicateCheck.key("ゴールドマン・サックス"),
                 WordCandidateDuplicateCheck.key("ゴールドマン　サックス!")
    assert_equal WordCandidateDuplicateCheck.key("ｶﾚｰらいす"), WordCandidateDuplicateCheck.key("カレーライス")
    assert_equal WordCandidateDuplicateCheck.key("ABC殺人事件"), WordCandidateDuplicateCheck.key("ａｂｃ殺人事件")
    assert_not_equal WordCandidateDuplicateCheck.key("カレーライス"), WordCandidateDuplicateCheck.key("カレライス")
    assert_not_equal WordCandidateDuplicateCheck.key("ハレ"), WordCandidateDuplicateCheck.key("バレ")
  end

  test "収録済みの語・別表記・他の候補に一致した相手を返し、自分自身は含めない" do
    target = WordCandidate.create!(surface: "カレー・ライス", status: :duplicate)
    variant = WordCandidate.create!(surface: "カリー", status: :duplicate)
    other = WordCandidate.create!(surface: "ゴールドマンサックス", status: :rejected)
    mine = WordCandidate.create!(surface: "ゴールドマン・サックス", status: :duplicate)
    lonely = WordCandidate.create!(surface: "どこにも無い言葉", status: :duplicate)

    matches = WordCandidateDuplicateCheck.new([ target, variant, mine, lonely ]).call

    assert_equal [ [ :word, words(:curry).id ] ], matches[target.id].map { |m| [ m.kind, m.word_id ] }
    assert_equal [ :variant ], matches[variant.id].map(&:kind)
    assert_equal [ other ], matches[mine.id].map(&:candidate)
    assert_empty matches[lonely.id]
  end
end
