require "test_helper"

class WordCandidateReviewTest < ActiveSupport::TestCase
  def review(candidates, context: :triage)
    WordCandidateReview.new(candidates, context: context)
  end

  test "仕分け: upload したままの語は拡張、重複の疑いがある語は除外、保留の語は保留、それ以外は採用を最初から選んでおく" do
    fresh = WordCandidate.create!(surface: "新しい言葉")
    duplicate = WordCandidate.create!(surface: "カレー・ライス")
    held = WordCandidate.create!(surface: "迷っている言葉", status: :held)
    # 拡張の元にした語・集めた語・表記を確かめ済みの語は、拡張し直さないので採用
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", expanded_at: Time.current)
    child = WordCandidate.create!(surface: "神龍寺ナーガ", **seed.expansion_attributes)
    notated = WordCandidate.create!(surface: "確かめた言葉", notated_at: Time.current)

    rows = review([ fresh, duplicate, held, seed, child, notated ]).rows

    assert_equal %w[expand reject hold keep keep keep], rows.map(&:default)
    assert_equal [ [], [ "duplicate" ], [], [], [], [] ], rows.map(&:flags)
    assert_equal %w[expand keep hold reject], review([]).choices
  end

  test "表記の確認: 立項に疑義がある語は保留、表記が変わった語には印を付ける(拡張は選べない)" do
    doubtful = WordCandidate.create!(surface: "とてつもなく大きな", status: :notated, entry_score: 2)
    renamed = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notated)
    renamed.update!(surface: "ゴールドマン・サックス", entry_score: 5)

    notation = review([ doubtful, renamed ], context: :notation)

    assert_equal %w[hold keep], notation.rows.map(&:default)
    assert_equal [ [ "doubtful" ], [ "changed" ] ], notation.rows.map(&:flags)
    assert_equal({ "doubtful" => 1, "changed" => 1 }, notation.flag_counts)
    assert_equal %w[keep hold reject], notation.choices
  end

  test "同じ元の語から増えた語を系統として括り、元の語1語だけの行は括らない" do
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", expanded_at: Time.current)
    child = WordCandidate.create!(surface: "神龍寺ナーガ", **seed.expansion_attributes)
    alone = WordCandidate.create!(surface: "ひとりの言葉")
    split_from = WordCandidate.create!(surface: "経済・経営学部", status: :rejected)
    part = WordCandidate.create!(surface: "経済学部", **split_from.expansion_attributes)

    groups = review(WordCandidate.triage.in_tree_order).groups

    assert_equal [ [ seed, child ], [ alone ], [ part ] ], groups.map { |group| group.rows.map(&:candidate) }
    assert_equal [ true, false, true ], groups.map(&:family?)
    assert_equal [ seed, alone, split_from ], groups.map(&:root)
    assert groups.first.root_row?(groups.first.rows.first)
  end
end
