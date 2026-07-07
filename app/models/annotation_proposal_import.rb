# word-annotation-research スキルの出力 JSON を annotation_proposals へ取り込む(Issue 38)。
# 語ごとに1件で、既に提案がある語は上書きして pending に戻す(再貼り付けで冪等)。
# 未知のマスタ名は解決せず payload にそのまま保持する(新設候補としてコンソールに出す)。
class AnnotationProposalImport
  # 取り込み結果。saved=保存(新規+上書き), unknown_word_ids=DB に無い word_id(取り込まない)。
  Result = Struct.new(:saved, :unknown_word_ids, keyword_init: true)

  # payload に保持するキー(これ以外は捨てる。想定外のデータを溜め込まない)。
  PAYLOAD_KEYS = %w[surface meaning genre_path genre_new entity_type part_of_speech
                    word_origins variants confidence notes entry_score entry_notes].freeze

  def initialize(json_text)
    @json_text = json_text.to_s
  end

  # JSON の形が読めないときは nil を返す(呼び出し側でエラー表示)。
  def import
    entries = parse
    return nil unless entries

    known_ids = Word.where(id: entries.keys).pluck(:id)
    unknown_ids = entries.keys - known_ids

    AnnotationProposal.transaction do
      known_ids.each do |word_id|
        proposal = AnnotationProposal.find_or_initialize_by(word_id: word_id)
        proposal.payload = entries[word_id]
        proposal.status = :pending
        proposal.save!
      end
    end

    Result.new(saved: known_ids.size, unknown_word_ids: unknown_ids)
  end

  private

  # { word_id => payload } に整える。word_id が無い・重複する行は後勝ちで単純化する。
  def parse
    data = JSON.parse(@json_text)
    proposals = data.is_a?(Hash) ? data["proposals"] : nil
    return nil unless proposals.is_a?(Array)

    entries = {}
    proposals.each do |entry|
      next unless entry.is_a?(Hash)

      word_id = entry["word_id"].to_i
      next if word_id.zero?

      entries[word_id] = entry.slice(*PAYLOAD_KEYS)
    end
    entries
  rescue JSON::ParserError
    nil
  end
end
