# 1語ぶんの「再調査(reannotation)用データ」の書き出し。
# アノテーション・コンソールで「この注釈は微妙だ」と思った語について、Claude Code の
# /reannotation に渡して項目単位(意味・ジャンル・特徴 等)で調べ直させるための JSON を作る。
#
# まとめての書き出し(AnnotationResearchExport)との違いは次の2点:
#   - 対象が1語で、注釈済み・提案取り込み済みの語も対象にできる。
#   - 現在のアノテーション内容(current)を提案 JSON と同じ形で同梱する。スキルは
#     これを「調べ直した結果と突き合わせる相手」として使い、再調査しない項目は
#     そのまま素通しして返す(取り込みは payload を丸ごと上書きするため、返す JSON は
#     常に語の全項目が揃っている必要がある)。
class ReannotationExport
  VERSION = "1".freeze
  FORMAT = "reannotation".freeze
  # 提案 payload のうち語義に属するキー(トップレベル形式の提案を senses へ畳むのに使う)。
  SENSE_KEYS = %w[reading meaning genre_path genre_new entity_type part_of_speech
                  word_origins linguistic_features variants].freeze
  # 語全体のメタ(語義に依らない)。
  META_KEYS = %w[entry_score entry_notes confidence notes].freeze

  def initialize(word, proposal = nil)
    @word = word
    @proposal = proposal
  end

  def as_json
    {
      "version" => VERSION,
      "format" => FORMAT,
      "word_id" => @word.id,
      "surface" => @word.surface,
      "reading" => @word.word_senses.map(&:reading).uniq.join("、"),
      "current" => current,
      "masters" => AnnotationMasters.as_json
    }
  end

  def to_json(*)
    JSON.pretty_generate(as_json)
  end

  private

  # 現在のアノテーション内容。人が保存した内容(saved)を正とし、まだ何も付いていない語
  # (取り込んだ提案を確認している最中で未保存)は提案の payload(proposal)を渡す。
  # どちらから採ったかは source で明示する(スキルの notes と、オーナーの判断材料になる)。
  def current
    return saved_current if annotated?
    return proposal_current if @proposal

    { "source" => "none", "senses" => sense_entries }
  end

  def saved_current
    { "source" => "saved", "senses" => sense_entries }.merge(proposal_meta)
  end

  # 提案 payload を現在値として渡す。トップレベル形式(単一語義の後方互換)の提案も
  # senses 配列へ畳んで渡し、スキルが受け取る形を1つに保つ。
  def proposal_current
    payload = @proposal.payload
    senses = payload["senses"].is_a?(Array) ? payload["senses"] : [ payload.slice(*SENSE_KEYS) ]
    { "source" => "proposal", "senses" => senses }.merge(payload.slice(*META_KEYS))
  end

  # 提案側だけが持つ語全体のメタ(立項スコア・確信度・メモ)。保存済みの語でも、
  # 取り込み時の提案が残っていれば再調査の手がかりとして渡す。
  def proposal_meta
    return {} unless @proposal

    @proposal.payload.slice(*META_KEYS)
  end

  # 語義に何か1つでも注釈が付いていれば「保存済みの内容がある」とみなす。
  def annotated?
    @word.word_senses.any? do |sense|
      sense.meaning.present? || sense.genre_id || sense.entity_type_id ||
        sense.part_of_speech_id || sense.word_origins.any? ||
        sense.word_sense_features.any? || sense.word_sense_variants.any?
    end
  end

  # 保存済みの語義を、提案 JSON と同じキー(genre_path / entity_type / ...)で書き出す。
  # 空の項目は落として、渡す JSON を読みやすくする。
  def sense_entries
    @word.word_senses.map do |sense|
      {
        "reading" => sense.reading,
        "meaning" => sense.meaning,
        "genre_path" => genre_path(sense.genre),
        "entity_type" => sense.entity_type&.name,
        "part_of_speech" => sense.part_of_speech&.name,
        "word_origins" => sense.word_origins.map(&:name).sort,
        "linguistic_features" => feature_entries(sense),
        "variants" => variant_entries(sense)
      }.compact_blank
    end
  end

  # 大→中→小の名前3つ。小分類以外が付いている異常データはそのまま出す(気付けるように)。
  def genre_path(genre)
    return [] unless genre

    genre.self_and_ancestors.map(&:name)
  end

  def feature_entries(sense)
    sense.word_sense_features.map do |feature|
      {
        "name" => feature.linguistic_feature&.name,
        "target" => feature.target,
        "target_reading" => feature.target_reading,
        "target_start" => feature.target_start
      }.compact
    end
  end

  def variant_entries(sense)
    sense.word_sense_variants.map do |variant|
      { "surface" => variant.surface, "reading" => variant.reading }.compact_blank
    end
  end
end
