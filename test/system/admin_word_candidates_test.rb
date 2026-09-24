require "application_system_test_case"

# 登録予定単語の仕分けの一覧(decision-list)。キーで選ぶと次の行へ進む・下端の件数の数え直し・
# Shift+クリックの範囲・系統のまとめて・印での絞り込み・行の中の手直し(F2 / Esc)・Ctrl+Enter の確定は、
# JS が無いと成り立たない。選択の既定・行き先そのものは結合テスト(triages_controller_test)で見る。
class AdminWordCandidatesTest < ApplicationSystemTestCase
  test "仕分けの一覧をキーボードとマウスで選び直し、Ctrl+Enter で確定する" do
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", expanded_at: Time.current)
    children = %w[神龍寺ナーガ 白秋ダイナソアーズ 盤戸スパイダーズ].map { |surface| WordCandidate.create!(surface: surface, **seed.expansion_attributes) }
    singles = %w[天上天下唯我独尊 王城ホワイトナイツ 独立行政法人国立文化財機構].map { |surface| WordCandidate.create!(surface: surface) }
    duplicate = WordCandidate.create!(surface: "カレー・ライス") # 収録済みの「カレーライス」と重なる(既定は除外)

    system_sign_in
    visit admin_candidates_triage_path
    wait_for_stimulus "decision-list"
    assert_decisions "kkkkkkkr", expand: 0, keep: 7, hold: 0, reject: 1

    # 系統の見出しの「すべて除外」で、その系統の行をそろえる
    click_via_js(expect_css: ".cand-row[data-decision=reject]", count: 5) do
      find(".cand-family .cand-family__action[data-decision=reject]")
    end
    assert_decisions "rrrrkkkr", expand: 0, keep: 3, hold: 0, reject: 5

    # キーで選ぶと次の行へ進む(↑ で戻れる)
    focus_decision(seed)
    press "e"
    assert_equal "decisions[#{children[0].id}]", active_element_name
    press "a"
    press "ArrowUp"
    press "x"
    assert_equal "decisions[#{children[1].id}]", active_element_name
    assert_decisions "errrkkkr", expand: 1, keep: 3, hold: 0, reject: 4

    # Shift+クリックで、直前に選んだ行からその行までを同じ処理にそろえる
    execute_script("arguments[0].click()", decision_input(singles[0], "hold"))
    execute_script("arguments[0].dispatchEvent(new MouseEvent('click', { bubbles: true, shiftKey: true }))",
                   decision_input(singles[2], "hold"))
    assert_decisions "errrhhhr", expand: 1, keep: 0, hold: 3, reject: 4

    # 印で絞り込むと、重複の疑いの行だけが見える(隠れた行の選択はそのまま)
    click_expecting(expect_css: ".cand-row", count: 1) { find(".cand-filter__chip[data-flag=duplicate]") }
    click_expecting(expect_css: ".cand-row", count: 8) { find(".cand-filter__chip[data-flag='']") }

    # F2 で行の中に「直す」を開き、Esc で取りやめると、その行の選択にフォーカスが戻る
    focus_decision(singles[0])
    press "F2"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(singles[0])} .cand-edit input[name='word_candidate[surface]']"
    assert wait_until { active_element_name == "word_candidate[surface]" }, "開いたフォームの表層形にフォーカスが移りませんでした"
    press "Escape"
    assert_no_selector ".cand-edit"
    assert wait_until { active_element_name == "decisions[#{singles[0].id}]" }, "行の選択にフォーカスが戻りませんでした"

    # Ctrl+Enter で確定する(拡張を選んだ語があるので拡張の画面へ進む)
    press "Enter", ctrl: true
    assert_current_path admin_candidates_expansion_path
    assert_equal %w[expanding rejected rejected rejected held held held duplicated],
                 [ seed, *children, *singles, duplicate ].map { |candidate| candidate.reload.status }
  end

  private

  # 行ごとの選択(k=採用 e=拡張 h=保留 r=除外 の並び)と、下端のバーの件数をまとめて確かめる。
  def assert_decisions(pattern, **counts)
    assert wait_until { row_decisions == pattern }, "行の選択が #{pattern} になりませんでした(#{row_decisions})"
    counts.each do |decision, count|
      assert_selector ".cand-bar__num[data-decision=#{decision}]", text: count.to_s, exact_text: true
    end
  end

  def row_decisions
    evaluate_script(<<~JS)
      [...document.querySelectorAll(".cand-row")].map((row) => ({ keep: "k", expand: "e", hold: "h", reject: "r" })[row.dataset.decision]).join("")
    JS
  end

  # 処理のラジオは見た目の上では透明なので(ボタン状のラベルの下に敷く)、JS でフォーカスを移す。
  def focus_decision(candidate)
    execute_script("arguments[0].focus()", find("input[name='decisions[#{candidate.id}]']:checked", visible: false))
  end

  def decision_input(candidate, decision)
    find("input[name='decisions[#{candidate.id}]'][value=#{decision}]", visible: false)
  end

  # フォーカスのある要素でキーを押す。このヘッドレス環境ではネイティブのキー入力がページに届かない
  # (Actions も要素の send_keys も。クリックが届かないのと同じ事情)ので、keydown を JS で送る。
  def press(key, ctrl: false)
    execute_script(<<~JS, key, ctrl)
      const [key, ctrlKey] = arguments;
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key, ctrlKey, bubbles: true, cancelable: true }));
    JS
  end

  def active_element_name
    evaluate_script("document.activeElement && document.activeElement.name")
  end
end
