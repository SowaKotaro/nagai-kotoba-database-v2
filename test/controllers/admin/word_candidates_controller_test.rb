require "test_helper"

# 登録予定単語の1語: 表示と、表層形・メモの手直し(確認の一覧では行の frame の中で開く)。
class Admin::WordCandidatesControllerTest < ActionDispatch::IntegrationTest
  test "表層形とメモを行の frame の中で手直しでき、空の表層形は保存しない" do
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notated)
    frame = ActionView::RecordIdentifier.dom_id(candidate, :word)

    get edit_admin_word_candidate_path(candidate)
    assert_select "turbo-frame##{frame} form[action=?]", admin_word_candidate_path(candidate)

    patch admin_word_candidate_path(candidate), params: { word_candidate: { surface: "ゴールドマン・サックス", note: "中黒" } }
    assert_redirected_to admin_word_candidate_path(candidate)
    assert_equal [ "ゴールドマン・サックス", "ゴールドマンサックス" ], candidate.reload.values_at(:surface, :original_surface)

    follow_redirect!
    assert_select "turbo-frame##{frame} .cand-word__surface", text: "ゴールドマン・サックス"
    assert_select "turbo-frame##{frame} .cand-word__was", text: /ゴールドマンサックス/

    # 空の表層形は保存せずフォームを出し直す
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "泥門デビルバッツ")

    patch admin_word_candidate_path(candidate), params: { word_candidate: { surface: " " } }
    assert_response :unprocessable_content
    assert_select ".form-errors li"
    assert_equal "泥門デビルバッツ", candidate.reload.surface
  end
end
