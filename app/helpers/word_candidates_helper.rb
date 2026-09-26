# 登録予定単語の前処理(仕分け・拡張・表記・登録待ち・すべての語)の画面用ヘルパー。
module WordCandidatesHelper
  # キーボードで処理を選ぶキー(確認の画面で、選んだら次の行へ進む)。表示は大文字。
  CANDIDATE_DECISION_KEYS = { "expand" => "e", "keep" => "a", "hold" => "h", "reject" => "x" }.freeze

  # 行を選んでまとめて処理する一覧(row-select)が受けるイベント。確認の一覧と「すべての語」で共用。
  # キーは window で受ける(行の外にフォーカスがあっても Esc で選択を外せるように)。
  CANDIDATE_ROW_SELECT_ACTIONS = %w[
    click->row-select#clicked mousedown->row-select#mousedown
    pointerdown->row-select#pointerdown pointermove->row-select#pointermove
    pointerup->row-select#pointerup pointercancel->row-select#pointerup
    keydown@window->row-select#keydown
  ].freeze

  # 確認の一覧(仕分け・表記の確認)の器に付ける Stimulus の設定。語ごとの処理(decision-list)と行の選択(row-select)を組む。
  # 同じキーは decision-list が先に受ける(行の中の keydown → window の keydown の順)。
  def candidate_review_data(form)
    {
      controller: "decision-list row-select",
      decision_list_form_value: form,
      row_select_selected_label_value: t("admin.word_candidates.select.selected"),
      action: [
        "change->decision-list#changed", "keydown->decision-list#keydown",
        "keydown@window->decision-list#windowKeydown", "turbo:frame-render->decision-list#frameRendered",
        "decision-list:applied->row-select#clear", "decision-list:filtered->row-select#clear",
        *CANDIDATE_ROW_SELECT_ACTIONS
      ].join(" ")
    }
  end

  # 「すべての語」の一覧の器に付ける Stimulus の設定(行の選択だけ)。
  def candidate_list_select_data
    {
      controller: "row-select",
      row_select_selected_label_value: t("admin.word_candidates.select.selected"),
      action: CANDIDATE_ROW_SELECT_ACTIONS.join(" ")
    }
  end

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
