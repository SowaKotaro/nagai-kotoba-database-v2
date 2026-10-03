# word-annotation-research スキルの出力 JSON を annotation_proposals へ取り込む(Issue 38)。
# 語ごとに1件で、既に提案がある語は上書きして pending に戻す(再貼り付けで冪等)。
# 未知のマスタ名は解決せず payload にそのまま保持する(新設候補としてコンソールに出す)。
# 種別: 調査 JSON の入出力。
class AnnotationProposalImport
  # 取り込み結果。saved=保存(新規+上書き), unknown_word_ids=DB に無い word_id(取り込まない)。
  Result = Struct.new(:saved, :unknown_word_ids, keyword_init: true)

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
  # 他の調査 JSON の取り込みと違い ResearchJson.array_at を使わない(```json フェンス付きは受け付けない)。
  # 寄せると受理する入力が広がるので、振る舞いを変える改修として別に扱う(計画書 §7.1)。
  def parse
    data = JSON.parse(@json_text)
    proposals = data.is_a?(Hash) ? data["proposals"] : nil
    return nil unless proposals.is_a?(Array)

    entries = {}
    proposals.each do |entry|
      next unless entry.is_a?(Hash)

      word_id = entry["word_id"].to_i
      next if word_id.zero?

      # トップレベルだけ選別し(AnnotationProposal::PAYLOAD_KEYS)、senses の中身は丸ごと保持する。
      # senses は複数語義(Issue 41)。meaning 等のトップレベル形式は単一語義の後方互換で読む。
      entries[word_id] = entry.slice(*AnnotationProposal::PAYLOAD_KEYS)
    end
    entries
  rescue JSON::ParserError
    nil
  end
end
