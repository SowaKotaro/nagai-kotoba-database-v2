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

  test "収録済みの語・別表記・並べていないほかの語(不要にした語を含む)に一致した相手を返す" do
    target = WordCandidate.create!(surface: "カレー・ライス")
    variant = WordCandidate.create!(surface: "カリー")
    other = WordCandidate.create!(surface: "ゴールドマンサックス", status: :rejected)
    mine = WordCandidate.create!(surface: "ゴールドマン・サックス")
    lonely = WordCandidate.create!(surface: "どこにも無い言葉")

    matches = WordCandidateDuplicateCheck.new([ target, variant, mine, lonely ]).call

    assert_equal [ [ :word, words(:curry).id ] ], matches[target.id].map { |m| [ m.kind, m.word_id ] }
    assert_equal [ :variant ], matches[variant.id].map(&:kind)
    assert_equal [ other ], matches[mine.id].map(&:candidate)
    assert_empty matches[lonely.id]
  end

  test "並べた語どうしは先の語を正とし、後ろの語だけを重複とみなす(両方を落とさない)" do
    first = WordCandidate.create!(surface: "ゴールドマンサックス")
    second = WordCandidate.create!(surface: "ゴールドマン・サックス")

    matches = WordCandidateDuplicateCheck.new([ first, second ]).call

    assert_empty matches[first.id]
    assert_equal [ first ], matches[second.id].map(&:candidate)
  end

  test "登録済みの登録予定単語は相手にしない(収録済みの語として当たるため、同じ語を2度出さない)" do
    WordCandidate.create!(surface: words(:curry).surface, status: :registered, word: words(:curry))
    target = WordCandidate.create!(surface: "カレーライス!")

    assert_equal [ :word ], WordCandidateDuplicateCheck.new([ target ]).call[target.id].map(&:kind)
  end
end
