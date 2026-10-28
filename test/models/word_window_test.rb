require "test_helper"

class WordWindowTest < ActiveSupport::TestCase
  setup do
    # id 順に並ぶ候補を 5 語つくる(読みはすべて同じ字数にして 1 つのスコープで引く)
    @ids = 5.times.map do |i|
      create_published_word(surface: "窓の候補#{i}", reading: "マドノコウホノゴ#{'アイウエオ'[i]}ゴ").id
    end
    @scope = WordSense.where(word_id: @ids)
  end

  test "起点より後ろの id から取り、足りなければ先頭へ回り込む" do
    assert_equal @ids[2, 2], WordWindow.word_ids(@scope, pivot_id: @ids[1], limit: 2)

    # 起点より後ろで足りなければ先頭へ回り込む
    assert_equal [ @ids[4], @ids[0], @ids[1] ], WordWindow.word_ids(@scope, pivot_id: @ids[3], limit: 3)

    # 起点が最大の id なら先頭から取る
    assert_equal @ids[0, 2], WordWindow.word_ids(@scope, pivot_id: @ids.last + 1, limit: 2)

    # 候補が上限以下なら全件を返す
    scope = @scope.where.not(word_id: @ids[2])
    assert_equal [ @ids[3], @ids[4], @ids[0], @ids[1] ], WordWindow.word_ids(scope, pivot_id: @ids[2], limit: 10)

    # 起点が違えば違う窓になる(語ごとに顔ぶれがずれる)
    first  = WordWindow.word_ids(@scope, pivot_id: @ids[0], limit: 2)
    second = WordWindow.word_ids(@scope, pivot_id: @ids[2], limit: 2)
    assert_not_equal first, second

    # 候補が無ければ空
    assert_equal [], WordWindow.word_ids(WordSense.none, pivot_id: @ids[0], limit: 6)
  end
end
