require "test_helper"

# 提案の一括承認(Issue 65)。厳格ゲートの判定と、承認=公開の副作用。
# haruhi_proposal は confidence high / 立項5 / 単一語義 / 全マスタ解決 / 新設0 なので基準の「対象」。
class BulkProposalApprovalTest < ActiveSupport::TestCase
  setup { @proposal = annotation_proposals(:haruhi_proposal) }

  test "厳格ゲート: 確信 high・立項4以上・単一語義・マスタがすべて既存の未適用の提案だけが対象" do
    assert BulkProposalApproval.eligible?(@proposal)
    assert_includes BulkProposalApproval.eligible, @proposal

    base = @proposal.payload
    {
      "確信度が high でない" => base.merge("confidence" => "medium"),
      "立項スコアが4未満" => base.merge("entry_score" => 3),
      "複数語義(取り違え防止)" => { "confidence" => "high", "entry_score" => 5,
                                    "senses" => [ { "meaning" => "A。" }, { "meaning" => "B。" } ] },
      "ジャンル小分類が既存の木に無い" => base.merge("genre_path" => %w[文学 日本文学 私小説]),
      "エンティティが未解決" => base.merge("entity_type" => "存在しない種別"),
      "語種が無い" => base.merge("word_origins" => []),
      "語種に未解決(新設)を含む" => base.merge("word_origins" => %w[和語 タミル語]),
      "特徴に未解決(新設)の名前を含む" => eligible_senses_payload(
        "linguistic_features" => [ { "name" => "存在しない特徴", "target" => "涼宮", "target_reading" => "すずみや" } ]
      )
    }.each do |reason, payload|
      @proposal.update!(payload: payload)
      assert_not BulkProposalApproval.eligible?(@proposal), reason
    end

    # applied の提案は対象外(冪等)
    @proposal.update!(payload: base)
    @proposal.applied!
    assert_not BulkProposalApproval.eligible?(@proposal)
    assert_empty BulkProposalApproval.eligible
  end

  # --- 承認(=公開)の副作用 ---
  test "approve! で対象語が公開され、語義が提案値で埋まり、提案が applied になる" do
    word = words(:pending_haruhi)
    sense = word_senses(:pending)

    result = BulkProposalApproval.new.approve!
    assert_equal 1, result.approved

    word.reload
    assert_not_nil word.annotated_at
    assert word.annotation_done?
    assert @proposal.reload.applied?

    sense.reload
    assert_match "谷川流", sense.meaning
    assert_equal genres(:small_novel), sense.genre
    assert_equal entity_types(:book_title), sense.entity_type
    assert_equal parts_of_speech(:noun), sense.part_of_speech
    assert_equal [ word_origins(:wago) ], sense.word_origins.to_a
  end

  test "approve! は特徴つき提案の特徴も該当部分つきで保存する" do
    @proposal.update!(payload: eligible_senses_payload(
      "linguistic_features" => [ { "name" => "連濁", "target" => "涼宮", "target_reading" => "すずみや" } ]
    ))
    assert BulkProposalApproval.eligible?(@proposal)

    BulkProposalApproval.new.approve!
    feature = word_senses(:pending).reload.word_sense_features.first
    assert_not_nil feature
    assert_equal linguistic_features(:rendaku), feature.linguistic_feature
    assert_equal "涼宮", feature.target
    assert_equal 0, feature.target_start # 先頭出現に補完
  end

  test "対象が無ければ何も公開しない" do
    @proposal.applied! # 唯一の pending 提案を外す
    assert_no_difference -> { Word.annotated.count } do
      assert_equal 0, BulkProposalApproval.new.approve!.approved
    end
  end

  private

  # 特徴込みで検証するための、ゲートを満たす senses 形式の payload。
  def eligible_senses_payload(extra = {})
    {
      "confidence" => "high", "entry_score" => 5,
      "senses" => [ {
        "meaning" => "谷川流のライトノベル。",
        "genre_path" => %w[文学 日本文学 小説],
        "entity_type" => "書籍名", "part_of_speech" => "名詞", "word_origins" => %w[和語]
      }.merge(extra) ]
    }
  end
end
