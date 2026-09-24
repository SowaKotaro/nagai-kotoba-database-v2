# 仕分け・表記の確認で、語ごとに選んだ処理(拡張 / 採用 / 保留 / 除外)をまとめて当てる。
#
# 送られてきた語のうち、その画面に並べたステータス(statuses)にいる語だけを動かす
# (表示のあとに別の画面で動かした語や、あとから入ってきた語を確認なしで動かさないため)。
# 行き先は WordCandidate#destination_for が決める。除外は照合をやり直し、一致があれば重複
# (相手をメモに残す)、無ければ不要にする。
class WordCandidateDecisions
  # decisions は { 語の ID => 処理 }。choices はその画面で選べる処理。
  def initialize(decisions, statuses:, choices:)
    @decisions = decisions.to_h.transform_keys(&:to_s)
    @statuses = statuses
    @choices = choices
  end

  # 移した先のステータスごとの語数({ "notating" => 9, ... })。動かなかった語(保留のまま等)は数えない。
  def call
    counts = Hash.new(0)
    WordCandidate.transaction do
      WordCandidate.where(id: @decisions.keys, status: @statuses).in_tree_order.each do |candidate|
        decision = @decisions[candidate.id.to_s].presence_in(@choices)
        status = decision && apply(candidate, decision)
        counts[status] += 1 if status
      end
    end
    counts
  end

  private

  def apply(candidate, decision)
    matches = decision == "reject" ? duplicate_check.matches_for(candidate.surface, except: candidate) : []
    status = candidate.destination_for(decision, duplicate: matches.any?)
    return if status == candidate.status

    note = I18n.t("admin.word_candidates.duplicate_note", other: matches.first.surface) if matches.any?
    candidate.update!(status: status, note: WordCandidate.append_note(candidate.note, note))
    status
  end

  # 除外の語が重複か不要かを分けるための照合(ほかの語すべてが相手。必要になったときだけ読み込む)。
  def duplicate_check
    @duplicate_check ||= WordCandidateDuplicateCheck.new
  end
end
