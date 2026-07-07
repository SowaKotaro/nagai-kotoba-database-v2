require "test_helper"

# Claude の提案(下書き)。payload の読み出しとマスタ名の解決(Issue 38)。
class AnnotationProposalTest < ActiveSupport::TestCase
  setup { @proposal = annotation_proposals(:haruhi_proposal) }

  test "payload から提案値を読み出せる" do
    assert_match "谷川流", @proposal.meaning
    assert_equal %w[文学 日本文学 小説], @proposal.genre_path
    assert_equal "書籍名", @proposal.entity_type_name
    assert_equal "名詞", @proposal.part_of_speech_name
    assert_equal %w[和語], @proposal.word_origin_names
    assert_equal [ "ハルヒ" ], @proposal.variants.map { |v| v["surface"] }
    assert_equal "high", @proposal.confidence
    assert_match "シリーズ第1作", @proposal.notes
  end

  test "ジャンルパスを木から末端(小分類)まで解決できる" do
    assert_equal genres(:small_novel), @proposal.resolved_genre
  end

  test "存在しない・途中までのジャンルパスは解決しない(新設候補)" do
    @proposal.payload["genre_path"] = %w[文学 日本文学 存在しない小分類]
    assert_nil @proposal.resolved_genre

    # 途中(中分類)までしか無いパスも、末端が小分類でないため解決しない
    @proposal.payload["genre_path"] = %w[文学 日本文学]
    assert_nil @proposal.resolved_genre
  end

  test "エンティティ・品詞・語種を名前で解決できる" do
    assert_equal entity_types(:book_title), @proposal.resolved_entity_type
    assert_equal parts_of_speech(:noun), @proposal.resolved_part_of_speech
    assert_equal [ word_origins(:wago) ], @proposal.resolved_word_origins.to_a
    assert_empty @proposal.unknown_word_origin_names
  end

  test "未知のマスタ名は解決せず新設候補として残る" do
    @proposal.payload["entity_type"] = "存在しないエンティティ"
    @proposal.payload["word_origins"] = %w[和語 タミル語]

    assert_nil @proposal.resolved_entity_type
    assert_equal %w[タミル語], @proposal.unknown_word_origin_names
  end

  test "語には提案は1件まで(上書き前提のユニーク制約)" do
    duplicate = AnnotationProposal.new(word: words(:pending_haruhi), payload: { "meaning" => "重複" })
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end
end
