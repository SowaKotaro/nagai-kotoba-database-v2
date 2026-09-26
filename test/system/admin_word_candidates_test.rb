require "application_system_test_case"

# 登録予定単語の確認の一覧(decision-list)と、行を選んでまとめて処理する操作(row-select)。
# キーで選ぶと次の行へ進む・下端の件数の数え直し・行を押して選ぶ・Shift+クリックの範囲・左端のなぞり・
# 系統を選ぶ・選んだ行にまとめて当てる・印での絞り込み・行の中の手直し(F2 / Esc)・Ctrl+Enter の確定は、
# JS が無いと成り立たない。選択の既定・行き先そのものは結合テスト(triages_controller_test)で見る。
class AdminWordCandidatesTest < ApplicationSystemTestCase
  test "仕分けの一覧をキーボードとマウスで選び直し、Ctrl+Enter で確定する" do
    seed = WordCandidate.create!(surface: "泥門デビルバッツ", expanded_at: Time.current)
    children = %w[神龍寺ナーガ 白秋ダイナソアーズ 盤戸スパイダーズ].map { |surface| WordCandidate.create!(surface: surface, **seed.expansion_attributes) }
    # upload したままの語(既定は拡張)
    singles = %w[天上天下唯我独尊 王城ホワイトナイツ 独立行政法人国立文化財機構].map { |surface| WordCandidate.create!(surface: surface) }
    duplicate = WordCandidate.create!(surface: "カレー・ライス") # 収録済みの「カレーライス」と重なる(既定は除外)

    system_sign_in
    visit admin_candidates_triage_path
    wait_for_stimulus "decision-list"
    assert_decisions "kkkkeeer", expand: 3, keep: 4, hold: 0, reject: 1

    # 系統の見出しの「この系統を選ぶ」で系統の行を選び、下端のバーの「除外」でまとめてそろえる(選択は外れる)
    click_via_js(expect_css: ".cand-bar__selected", text: "4 語を選択中") { find(".cand-family__action") }
    click_via_js(expect_css: ".cand-bar__counts:not([hidden])") { find(".cand-bar__action--reject") }
    assert_decisions "rrrreeer", expand: 3, keep: 0, hold: 0, reject: 5
    assert_equal [], selected_surfaces

    # キーで選ぶと次の行へ進む(↑ で戻れる)
    focus_decision(seed)
    press "e"
    assert_equal "decisions[#{children[0].id}]", active_element_name
    press "a"
    press "ArrowUp"
    press "x"
    assert_equal "decisions[#{children[1].id}]", active_element_name
    assert_decisions "errreeer", expand: 4, keep: 0, hold: 0, reject: 4

    # 行を押して選び、Shift+クリックで範囲を広げる。選んでいる行があれば、処理のキーはその行すべてに効く
    click_row(singles[0])
    click_row(singles[2], shift: true)
    assert_equal singles.map(&:surface), selected_surfaces
    press "h"
    assert_decisions "errrhhhr", expand: 1, keep: 0, hold: 3, reject: 4
    assert_equal [], selected_surfaces

    # 左端の選択の列をなぞると、通った行をまとめて選ぶ。Esc で選択を外す(処理はそのまま)
    sweep_rows(children[0], children[2])
    assert_equal children.map(&:surface), selected_surfaces
    press "Escape"
    assert wait_until { selected_surfaces.empty? }, "Esc で選択が外れませんでした"
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

  test "すべての語で行を押して選び(Shift+クリックで範囲)、下端のバーからまとめて移す" do
    words = %w[一番目の言葉 二番目の言葉 三番目の言葉 四番目の言葉].map { |surface| WordCandidate.create!(surface: surface, status: :rejected) }
    registered = WordCandidate.create!(surface: words(:curry).surface, status: :registered)

    system_sign_in
    visit admin_candidates_list_path
    wait_for_stimulus "row-select"
    assert_selector ".cand-bar__hint"

    click_table_row(words[0])
    click_table_row(words[2], shift: true)
    # 登録済みの語は選べない
    click_table_row(registered)
    assert_selector ".cand-bar__selected", text: "3 語を選択中"

    click_via_js(expect_css: "#flash", text: "3 語を「仕分け待ち」にしました。") { find(".cand-bar button[value=triage]") }
    assert_equal %w[triage triage triage rejected registered], [ *words, registered ].map { |candidate| candidate.reload.status }
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

  # 選んでいる行(row-select)の表層形を、並んでいる順に。
  def selected_surfaces
    evaluate_script(<<~JS)
      [...document.querySelectorAll(".cand-row[data-selected=true] .cand-word__surface")].map((surface) => surface.textContent)
    JS
  end

  # 行の語の部分を押す(shift: true で Shift+クリック)。ネイティブのクリックは届かないことがあるので JS で送る。
  def click_row(candidate, shift: false)
    execute_script("arguments[0].dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, shiftKey: arguments[1] }))",
                   find("##{ActionView::RecordIdentifier.dom_id(candidate)} .cand-word__surface"), shift)
  end

  # すべての語の表の行(状態の欄)を押す。
  def click_table_row(candidate, shift: false)
    execute_script("arguments[0].dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, shiftKey: arguments[1] }))",
                   find(".cand-table__row", text: candidate.surface).find(".cand-table__status"), shift)
  end

  # 左端の選択の列を、from の行から to の行までなぞる(ポインタのイベントを JS で送る)。
  def sweep_rows(from, to)
    start, finish = [ from, to ].map { |candidate| find("##{ActionView::RecordIdentifier.dom_id(candidate)} .row-check input", visible: false) }
    execute_script(<<~JS, start, finish)
      const [start, finish] = arguments;
      start.scrollIntoView({ block: "center" });
      const at = (element) => { const rect = element.getBoundingClientRect(); return { clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2 }; };
      const fire = (type, point) => start.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 1, pointerType: "mouse", isPrimary: true, button: 0, ...point }));
      fire("pointerdown", at(start));
      fire("pointermove", at(finish));
      fire("pointerup", at(finish));
    JS
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
