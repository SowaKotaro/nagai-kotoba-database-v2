require "test_helper"

# 登録予定単語の一覧・upload・手直し。認可と、絞り込み・処理の振り分け。
class Admin::WordCandidatesControllerTest < ActionDispatch::IntegrationTest
  test "未ログインでは一覧も upload も弾く" do
    get admin_word_candidates_path
    assert_redirected_to new_session_path

    assert_no_difference "WordCandidate.count" do
      post admin_word_candidates_path, params: { word_candidate_intake: { text: "泥門デビルバッツ" } }
    end
  end

  test "箇条書きを upload し、upload の語に絞った一覧へ戻る。空の入力はフォームを出し直す" do
    sign_in_as(admins(:one))
    get new_admin_word_candidate_path
    assert_response :success
    assert_select ".candidate-flow__item.is-current", text: /upload/

    assert_difference "WordCandidate.upload.count", 2 do
      post admin_word_candidates_path, params: { word_candidate_intake: { text: "1. 泥門デビルバッツ\n2. 王城ホワイトナイツ" } }
    end
    assert_redirected_to admin_word_candidates_path(status: "upload")

    post admin_word_candidates_path, params: { word_candidate_intake: { text: "\n \n" } }
    assert_response :unprocessable_content
  end

  test "ステータスで絞り込み、expand で増えた語は元の語の直後に「↳」付きで並ぶ" do
    sign_in_as(admins(:one))
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", status: :expand, expanded_at: Time.current)
    WordCandidate.create!(surface: "王城ホワイトナイツ", status: :duplicate)
    WordCandidate.create!(surface: "神龍寺ナーガ", status: :expand, **seed.expansion_attributes)
    WordCandidate.create!(surface: "白秋ダイナソアーズ", status: :expand, **seed.expansion_attributes)

    get admin_word_candidates_path(status: "expand")
    assert_response :success
    assert_select "tbody tr", 3
    assert_select "tbody tr:nth-child(2) .candidate-surface__branch", text: "↳"
    assert_select "tbody tr:nth-child(3) .candidate-surface__branch", text: ""
    assert_select "tbody .candidate-badge--expand", 3
  end

  test "選んだ語を expand・duplicate に回すとその段の画面へ、不要にすると一覧に戻る" do
    sign_in_as(admins(:one))
    first = WordCandidate.create!(surface: "泥門デビルバッツ")
    second = WordCandidate.create!(surface: "王城ホワイトナイツ")

    post bulk_admin_word_candidates_path, params: { candidate_ids: [ first.id ], commit: "to_expand" }
    assert_redirected_to admin_candidates_expansion_path
    post bulk_admin_word_candidates_path, params: { candidate_ids: [ second.id ], commit: "to_duplicate" }
    assert_redirected_to admin_candidates_duplicate_check_path
    assert_equal %w[expand duplicate], [ first.reload.status, second.reload.status ]

    post bulk_admin_word_candidates_path, params: { candidate_ids: [ second.id ], commit: "to_rejected", status: "duplicate" }
    assert_redirected_to admin_word_candidates_path(status: "duplicate")
    assert_predicate second.reload, :rejected?
  end

  test "処理や語が選ばれていなければ知らせて何もしない(登録済みや done には手で移せない)" do
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "泥門デビルバッツ")

    post bulk_admin_word_candidates_path, params: { candidate_ids: [ candidate.id ], commit: "to_registered" }
    assert_equal I18n.t("admin.word_candidates.bulk.no_action"), flash[:alert]
    post bulk_admin_word_candidates_path, params: { commit: "to_expand" }
    assert_equal I18n.t("admin.word_candidates.bulk.no_selection"), flash[:alert]
    assert_predicate candidate.reload, :upload?
  end

  test "表層形とメモを手直しでき、元の表記は残る" do
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notation)

    get edit_admin_word_candidate_path(candidate)
    assert_response :success

    patch admin_word_candidate_path(candidate), params: { word_candidate: { surface: "ゴールドマン・サックス", note: "中黒" } }
    assert_redirected_to admin_word_candidates_path(status: "notation")
    assert_equal [ "ゴールドマン・サックス", "ゴールドマンサックス" ], candidate.reload.values_at(:surface, :original_surface)
  end
end
