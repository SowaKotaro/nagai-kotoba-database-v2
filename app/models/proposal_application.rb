# 提案(AnnotationProposal)の値を word の word_senses へ初期値として組み立てる(保存はしない)。
# コンソールの「提案を反映」(GET・Issue 38/41/63)と一括承認(Issue 65)で規則を共有する。
# 既存の語義(一括登録で読みだけ入った語義など)を先頭から使い回し、足りない分は同じ読みで
# 新しい語義を建てる。マスタ名 → レコードの解決は AnnotationProposal::SenseProposal が担う。
#
# 語種は has_many :through。GET 反映(persist: false)は永続化済み語義に即書き込みしないよう
# association の target をメモリ上で差し替えるだけにする。保存前提の一括承認(persist: true)は
# word_origin_ids= の setter で join を確定させる(target を先に立てると setter が「変化なし」と
# 判断して join を書かないため、保存時は target を使わず setter に一本化する)。
class ProposalApplication
  def initialize(word, proposal, persist: false)
    @word = word
    @proposal = proposal
    @persist = persist
  end

  # 提案の各語義を word_senses へ割り当てる(build のみ・保存しない)。組み立てた word を返す。
  def build
    base_reading = @word.word_senses.first&.reading
    existing = @word.word_senses.reject(&:marked_for_destruction?)

    @proposal.senses.each_with_index do |sense_proposal, index|
      sense = existing[index] ||
              @word.word_senses.build(reading: sense_proposal.reading.presence || base_reading)
      apply_sense(sense, sense_proposal)
    end
    @word
  end

  private

  # 1つの語義に、対応する語義提案の値を初期値として流し込む。
  def apply_sense(sense, sense_proposal)
    sense.reading = sense_proposal.reading if sense_proposal.reading.present? && sense.reading.blank?
    sense.meaning = sense_proposal.meaning if sense_proposal.meaning
    apply_genre(sense, sense_proposal)
    sense.entity_type_id = sense_proposal.resolved_entity_type&.id if sense_proposal.entity_type_name
    sense.part_of_speech_id = sense_proposal.resolved_part_of_speech&.id if sense_proposal.part_of_speech_name
    apply_origins(sense, sense_proposal)
    build_variants(sense, sense_proposal)
    build_features(sense, sense_proposal)
  end

  # 語種(has_many :through)。保存前提なら setter で join を確定させ、GET 反映なら target を
  # メモリ上で差し替えるだけにする(永続化済み語義への即書き込みを避ける)。
  def apply_origins(sense, sense_proposal)
    origins = sense_proposal.resolved_word_origins.to_a
    return if origins.empty?

    if @persist
      sense.word_origin_ids = origins.map(&:id)
    else
      sense.association(:word_origins).target = origins.dup
    end
  end

  # 提案ジャンルを既存の木で解決する。小分類まで在れば genre_id を確定させ、大・中までしか
  # 無ければ preselect にその祖先 id を積み、ピッカーをそこまで開かせる(末端はその場追加で選ぶ)。
  def apply_genre(sense, sense_proposal)
    chain = sense_proposal.resolved_genre_chain
    if chain.last&.small?
      sense.genre_id = chain.last.id
    elsif chain.any?
      sense.genre_preselect_ids = chain.map(&:id)
    end
  end

  # 提案の別表記を、まだ無いものだけ足す(重複追加しない)。
  def build_variants(sense, sense_proposal)
    existing = sense.word_sense_variants.map(&:surface)
    sense_proposal.variants.each do |variant|
      next if existing.include?(variant["surface"])

      sense.word_sense_variants.build(surface: variant["surface"], reading: variant["reading"])
    end
  end

  # 提案の言語的特徴を、既存マスタに解決できるものだけ足す(重複追加しない・Issue 63)。
  # target_start はモデルの before_validation が先頭出現に補完し、feature-range が
  # ロード時に該当部分のハイライトを復元する。target/target_reading は保存時に部分一致検証を
  # 受ける(外れていれば人が直す)。マスタに無い特徴名は反映せず、新設候補としてパネルに出る。
  def build_features(sense, sense_proposal)
    existing = sense.word_sense_features.map { |feature| [ feature.linguistic_feature_id, feature.target ] }
    sense_proposal.linguistic_features.each do |feature|
      linguistic_feature = sense_proposal.resolved_linguistic_feature(feature)
      next unless linguistic_feature
      next if existing.include?([ linguistic_feature.id, feature["target"] ])

      sense.word_sense_features.build(
        linguistic_feature: linguistic_feature,
        target: feature["target"],
        target_reading: feature["target_reading"]
      )
    end
  end
end
