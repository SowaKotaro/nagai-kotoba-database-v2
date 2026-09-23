# 登録予定単語の前処理(一覧・upload と expand・duplicate・notation の各段)の画面用ヘルパー。
module WordCandidatesHelper
  # ステータスごとの語数(流れ図の件数)。1リクエストで何度呼んでも1回だけ数える。
  def candidate_status_counts
    @candidate_status_counts ||= WordCandidate.group(:status).count
  end

  # 流れ図の各段の画面。upload は貼り付け画面。
  def candidate_step_path(step)
    case step
    when "upload" then new_admin_word_candidate_path
    when "expand" then admin_candidates_expansion_path
    when "duplicate" then admin_candidates_duplicate_check_path
    when "notation" then admin_candidates_notation_path
    end
  end

  # expand で増えた語の枝の印。元の語の直後の1語目にだけ「↳」を付け、2語目以降は字下げだけにする。
  def candidate_branch_mark(candidate, previous)
    previous&.seed_id == candidate.seed_id ? "" : "↳"
  end
end
