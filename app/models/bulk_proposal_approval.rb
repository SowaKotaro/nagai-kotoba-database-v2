# 提案の一括承認(Issue 65)。厳格ゲートを満たす pending 提案だけを、プレビュー後にまとめて
# 承認する。承認 = 提案値で word_senses を組んで保存し、公開(mark_annotated)、提案を applied
# にする。危うい提案(低信頼・低スコア・複数語義・新設マスタあり・マスタ未解決)は対象外で、
# 人手キューに残してコンソールで1語ずつ確認する。
#
# ゲート判定は各提案の payload と各マスタの find_by で行うため、対象数に比例してクエリが増える
# (管理者が随時叩く操作なので許容。件数が桁違いに増えたら事前絞り込みを検討)。
class BulkProposalApproval
  Result = Struct.new(:approved, keyword_init: true)

  # ゲート(厳格・2026-07-16 オーナー選択): これを全部満たす pending 提案だけを一括対象にする。
  # 1つでも欠けたら対象外(=人手キューでコンソール承認する)。
  def self.eligible?(proposal)
    return false unless proposal.pending?
    return false unless proposal.confidence == "high"
    return false unless proposal.entry_score && proposal.entry_score >= 4
    return false unless proposal.senses.size == 1

    sense = proposal.senses.first
    sense.resolved_genre.present? &&              # ジャンル小分類(末端)まで既存の木で解決
      sense.resolved_entity_type.present? &&
      sense.resolved_part_of_speech.present? &&
      sense.word_origin_names.present? &&
      sense.unknown_word_origin_names.empty? &&   # 語種はすべて既存に解決(新設0)
      sense.linguistic_features.all? { |feature| sense.resolved_linguistic_feature(feature) }
  end

  # 一括対象の pending 提案(word を preload)。プレビューと承認で共有する。
  def self.eligible
    AnnotationProposal.pending
                      .includes(word: { word_senses: :word_origins })
                      .select { |proposal| eligible?(proposal) }
  end

  attr_reader :proposals

  def initialize(proposals = self.class.eligible)
    @proposals = proposals
  end

  def count
    @proposals.size
  end

  # まとめて承認して公開する。1件でも保存に失敗したら全体を巻き戻す。
  # 冪等: applied になった提案は次回の eligible に出ない(再承認されない)。
  def approve!
    AnnotationProposal.transaction do
      @proposals.each { |proposal| approve_one(proposal) }
    end
    Result.new(approved: count)
  end

  private

  def approve_one(proposal)
    word = proposal.word
    # persist: true で語種の join も setter で確定させる(GET 反映と違い保存するため)。
    ProposalApplication.new(word, proposal, persist: true).build
    word.word_senses.each(&:save!) # 新規の特徴・別表記も autosave される
    word.mark_annotated
    word.save!
    proposal.applied!
  end
end
