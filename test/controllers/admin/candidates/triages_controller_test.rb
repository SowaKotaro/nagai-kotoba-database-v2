require "test_helper"

# 仕分け(登録予定単語の入口): 貼り付けて追加し、語ごとに選んだ処理を一度に確定する。
class Admin::Candidates::TriagesControllerTest < ActionDispatch::IntegrationTest
  test "未ログインでは一覧も追加も確定も弾く" do
    candidate = WordCandidate.create!(surface: "泥門デビルバッツ")

    get admin_candidates_triage_path
    assert_redirected_to new_session_path
    assert_no_difference "WordCandidate.count" do
      post admin_candidates_triage_path, params: { word_candidate_intake: { text: "王城ホワイトナイツ" } }
    end
    patch admin_candidates_triage_path, params: { decisions: { candidate.id => "reject" } }
    assert_predicate candidate.reload, :triage?
  end

  test "箇条書きを追加すると仕分けに戻り、空の入力は貼り付け欄を開いたまま出し直す" do
    sign_in_as(admins(:one))

    assert_difference "WordCandidate.triage.count", 2 do
      post admin_candidates_triage_path, params: { word_candidate_intake: { text: "1. 泥門デビルバッツ\n2. 王城ホワイトナイツ" } }
    end
    assert_redirected_to admin_candidates_triage_path
    assert_equal I18n.t("admin.candidates.triages.create.created", count: 2), flash[:notice]

    post admin_candidates_triage_path, params: { word_candidate_intake: { text: "\n \n" } }
    assert_response :unprocessable_content
    assert_select "details.cand-intake[open]"
  end

  test "語ごとに処理を選ぶ行を、系統で括り、既定を選んだ状態で並べる(保留は末尾に畳む)" do
    sign_in_as(admins(:one))
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", expanded_at: Time.current)
    child = WordCandidate.create!(surface: "神龍寺ナーガ", **seed.expansion_attributes)
    fresh = WordCandidate.create!(surface: "天上天下唯我独尊")
    duplicate = WordCandidate.create!(surface: "カレー・ライス")
    held = WordCandidate.create!(surface: "迷っている言葉", status: :held)

    get admin_candidates_triage_path
    assert_response :success
    assert_select ".cand-steps__link[aria-current=page]", text: /#{I18n.t("admin.word_candidates.stages.triage.name")}/
    assert_select ".cand-family", 1 do
      assert_select ".cand-row", 2
      assert_select ".cand-row--child##{ActionView::RecordIdentifier.dom_id(child)}"
    end
    assert_select "input[name='decisions[#{seed.id}]'][value=keep][checked]"
    assert_select "input[name='decisions[#{fresh.id}]'][value=expand][checked]"
    assert_select "input[name='decisions[#{duplicate.id}]'][value=reject][checked]"
    assert_select "##{ActionView::RecordIdentifier.dom_id(duplicate)} .cand-word__match a[href=?]", word_path(words(:curry))
    assert_select "details#held:not([open]) input[name='decisions[#{held.id}]'][value=hold][checked]"
    assert_select ".cand-bar__num[data-decision=expand]", text: "1"
    assert_select ".cand-bar__num[data-decision=keep]", text: "2"
  end

  test "確定すると選んだ処理の行き先へ移し、拡張を選んだ語があれば拡張の画面へ、採用だけなら表記の画面へ進む" do
    sign_in_as(admins(:one))
    seed = WordCandidate.create!(surface: "泥門デビルバッツ")
    keep = WordCandidate.create!(surface: "天上天下唯我独尊")

    # 送った順ではなく、流れの順(拡張待ち → 表記待ち → … → 不要)で知らせる
    patch admin_candidates_triage_path, params: { decisions: { keep.id => "keep", seed.id => "expand" } }
    assert_redirected_to admin_candidates_expansion_path
    assert_equal %w[expanding notating], [ seed.reload.status, keep.reload.status ]
    assert_equal "拡張待ち 1 語 / 表記待ち 1 語", flash[:notice]

    other = WordCandidate.create!(surface: "王城ホワイトナイツ")
    patch admin_candidates_triage_path, params: { decisions: { other.id => "keep" } }
    assert_redirected_to admin_candidates_notation_path

    # 何も動かなければ知らせて仕分けに留まる(表示のあとにほかの画面で動かした語は動かさない)
    patch admin_candidates_triage_path, params: { decisions: { other.id => "reject" } }
    assert_redirected_to admin_candidates_triage_path
    assert_equal I18n.t("admin.candidates.triages.update.nothing"), flash[:alert]
    assert_predicate other.reload, :notating?
  end
end
