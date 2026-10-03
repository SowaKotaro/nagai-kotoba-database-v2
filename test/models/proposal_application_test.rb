require "test_helper"

# 提案の値を語義へ組み立てる規則(ProposalApplication)。反映の画面からの使われ方は
# Admin::AnnotationsControllerTest、一括承認は BulkProposalApprovalTest で見る。
class ProposalApplicationTest < ActiveSupport::TestCase
  # 提案に target_start を書いても、反映では使わない。特徴は保存時に先頭の出現へ補完される。
  test "提案の target_start は反映で使わず、保存すると特徴は先頭の出現に付く" do
    word = Word.create!(surface: "ゆめゆめのゆめ")
    word.word_senses.create!(reading: "ユメユメノユメ")
    proposal = AnnotationProposal.new(word: word, payload: {
      "senses" => [ { "linguistic_features" => [
        { "name" => linguistic_features(:rendaku).name, "target" => "ゆめ", "target_reading" => "ユメ", "target_start" => 5 }
      ] } ]
    })

    ProposalApplication.new(word, proposal).build
    feature = word.word_senses.first.word_sense_features.first
    assert_nil feature.target_start

    word.save!
    assert_equal 0, feature.reload.target_start
  end

  # genre_new は取り込みでは保持されるが、反映側に読む口が無い。新設候補かどうかは名前で決まる。
  test "提案の genre_new は読まれない(新設候補かどうかは名前を引けたかで決まる)" do
    sense_proposal = AnnotationProposal.new(payload: { "senses" => [ { "genre_new" => true } ] }).senses.first
    assert_not sense_proposal.respond_to?(:genre_new)
  end
end
