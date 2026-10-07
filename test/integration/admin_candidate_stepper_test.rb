require "test_helper"

# 登録予定単語の段の見出し(admin/candidates/_stepper。段の定義は WordCandidate::STAGES)。
# 4段を流れの順に各段の画面へつなぎ、段にいる語数を添え、開いている段に現在地の印を付ける。
class AdminCandidateStepperTest < ActionDispatch::IntegrationTest
  test "4段を各段の画面へつなぎ、段にいる語数と、表記の段で結果を確かめる語数を出す" do
    sign_in_as(admins(:one))
    WordCandidate.create!(surface: "仕分け待ちの言葉")
    WordCandidate.create!(surface: "表記を待つ言葉", status: :notating)
    WordCandidate.create!(surface: "表記を確かめる言葉", status: :notated)
    WordCandidate.create!(surface: "登録待ちの言葉", status: :ready)
    WordCandidate.create!(surface: "迷っている言葉", status: :held)

    get admin_candidates_notation_path
    assert_equal [ admin_candidates_triage_path, admin_candidates_expansion_path, admin_candidates_notation_path,
                   admin_candidates_registration_path ], css_select(".cand-steps__link").map { |link| link["href"] }
    assert_equal %w[1 0 2 1], css_select(".cand-steps__count").map { |count| count.children.first.text }
    assert_select ".cand-steps__link[aria-current=page][href=?]", admin_candidates_notation_path
    # 表記の段だけ、/notation の結果を確かめる語の数を案内の代わりに出す(保留の語はどの段にも数えない)
    assert_select ".cand-steps__todo", 1
    assert_select ".cand-steps__link[href=?] .cand-steps__todo", admin_candidates_notation_path,
                  text: I18n.t("admin.word_candidates.stages.notation.reviewing", count: 1)
    assert_select ".cand-steps__aside a[href=?]", admin_candidates_triage_path(held: 1, anchor: "held"),
                  text: I18n.t("admin.word_candidates.stages.held", count: 1)

    get admin_candidates_registration_path
    assert_select ".cand-steps__link[aria-current=page][href=?]", admin_candidates_registration_path
    get admin_candidates_list_path
    assert_select ".cand-steps__link[aria-current=page]", 0
    assert_select ".cand-steps__aside a[aria-current=page][href=?]", admin_candidates_list_path
  end
end
