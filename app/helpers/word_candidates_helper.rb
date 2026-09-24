# 登録予定単語の前処理(仕分け・拡張・表記・登録待ち・すべての語)の画面用ヘルパー。
module WordCandidatesHelper
  # キーボードで処理を選ぶキー(確認の画面で、選んだら次の行へ進む)。表示は大文字。
  CANDIDATE_DECISION_KEYS = { "expand" => "e", "keep" => "a", "hold" => "h", "reject" => "x" }.freeze

  # ステータスごとの語数。1リクエストで何度呼んでも1回だけ数える。
  def candidate_status_counts
    @candidate_status_counts ||= WordCandidate.group(:status).count
  end

  # 4段の見出しの件数(その段にいる語の数)。
  def candidate_stage_count(stage)
    WordCandidate::STAGES.fetch(stage).sum { |status| candidate_status_counts.fetch(status, 0) }
  end

  # 4段それぞれの画面。
  def candidate_stage_path(stage)
    case stage
    when "triage" then admin_candidates_triage_path
    when "expand" then admin_candidates_expansion_path
    when "notation" then admin_candidates_notation_path
    when "ready" then admin_candidates_registration_path
    end
  end

  def candidate_status_label(status)
    t("admin.word_candidates.statuses.#{status}")
  end

  def candidate_decision_key(decision)
    CANDIDATE_DECISION_KEYS.fetch(decision)
  end

  # 照合で一致した相手へのリンク(収録済みの語は公開ページ、登録予定単語はその語の画面)。
  # 確認の画面で選んだ処理を失わないよう、別のタブで開く。
  def candidate_match_link(match, tabindex: nil)
    path = match.candidate ? admin_word_candidate_path(match.candidate) : word_path(match.word_id)
    link_to match.surface, path, target: "_blank", rel: "noopener", tabindex: tabindex
  end

  # 一致した相手の種類(「収録済み」「収録済みの別表記」「登録予定・不要」など)。
  def candidate_match_kind(match)
    return t("admin.word_candidates.match.#{match.kind}") unless match.candidate

    t("admin.word_candidates.match.candidate", status: candidate_status_label(match.candidate.status))
  end
end
