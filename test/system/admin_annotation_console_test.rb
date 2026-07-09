require "application_system_test_case"

# アノテーション・コンソールの実機挙動。統合テストでは動かない Stimulus
# (genre-picker の段階表示 / 提案の反映 / 用語解説パネル)をブラウザで担保する。
class AdminAnnotationConsoleTest < ApplicationSystemTestCase
  setup do
    @word = words(:pending_haruhi)
    system_sign_in
  end

  test "ジャンルを大→中→小と選んで保存すると、注釈済みになり次の語へ進む" do
    visit admin_annotation_path(@word)
    wait_for_stimulus "genre-picker"

    # 段階表示ピッカー: 大分類を選ぶと中分類が現れ、中を選ぶと小が現れる(children を fetch)
    within ".ann-genre" do
      click_expecting(expect_css: ".ann-chip", text: "日本文学") { find("button.ann-chip", exact_text: "文学") }
      click_expecting(expect_css: ".ann-chip", text: "小説") { find("button.ann-chip", exact_text: "日本文学") }
      # 末端(小分類)を選ぶとチップが選択状態(is-on)になり、隠しフィールド genre_id に入る
      click_expecting(expect_css: ".ann-chip.is-on", text: "小説") { find("button.ann-chip", exact_text: "小説") }
    end
    assert_equal genres(:small_novel).id.to_s, find(".js-genre-value", visible: false).value

    # 次の未注釈(bermuda)のコンソールへ進む
    click_expecting(expect_css: "h1.ann-word", text: words(:pending_bermuda).surface, wait: 10) do
      find("input[type=submit][value='#{I18n.t("admin.annotations.save_next")}']")
    end
    # 保存した語は注釈済みになり、選んだジャンルが付いている
    assert_not_nil @word.reload.annotated_at
    assert_equal genres(:small_novel).id, word_senses(:pending).reload.genre_id
  end

  # 最低限のアノテーション項目(読み・語種・ジャンル・品詞・エンティティ)が揃うと
  # 語義カードの枠が緑(is-complete)になる。保存できるかどうかとは無関係の目印。
  test "最低限の項目が揃うと語義カードが完了表示になり、ひとつ欠けると戻る" do
    visit admin_annotation_path(@word)
    wait_for_stimulus "sense-completeness"

    # 初期状態は読みだけ。ジャンル・語種・品詞・エンティティが未設定
    assert_no_selector ".ann-sense.is-complete"

    choose_hidden_input "input[type=checkbox][value='#{word_origins(:wago).id}']"
    choose_hidden_input "input[type=radio][value='#{parts_of_speech(:noun).id}']"
    choose_hidden_input "input[type=radio][value='#{entity_types(:book_title).id}']"
    # ジャンルがまだ小分類まで決まっていないので完了にはならない
    assert_no_selector ".ann-sense.is-complete"

    within ".ann-genre" do
      click_expecting(expect_css: ".ann-chip", text: "日本文学") { find("button.ann-chip", exact_text: "文学") }
      click_expecting(expect_css: ".ann-chip", text: "小説") { find("button.ann-chip", exact_text: "日本文学") }
      click_expecting(expect_css: ".ann-chip.is-on", text: "小説") { find("button.ann-chip", exact_text: "小説") }
    end
    assert_selector ".ann-sense.is-complete"

    # 読みを消せば完了表示は外れる
    find(".ann-reading").set("")
    assert_no_selector ".ann-sense.is-complete"
  end

  test "ジャンルが中分類止まりでは語義カードは完了表示にならない" do
    visit admin_annotation_path(@word)
    wait_for_stimulus "sense-completeness"

    choose_hidden_input "input[type=checkbox][value='#{word_origins(:wago).id}']"
    choose_hidden_input "input[type=radio][value='#{parts_of_speech(:noun).id}']"
    choose_hidden_input "input[type=radio][value='#{entity_types(:book_title).id}']"

    within ".ann-genre" do
      click_expecting(expect_css: ".ann-chip", text: "日本文学") { find("button.ann-chip", exact_text: "文学") }
      click_expecting(expect_css: ".ann-chip", text: "小説") { find("button.ann-chip", exact_text: "日本文学") }
    end
    # 小分類を選ぶまで genre_id は空のまま
    assert_equal "", find(".js-genre-value", visible: false).value
    assert_no_selector ".ann-sense.is-complete"
  end

  test "用語解説パネルを開くと特徴の定義と例が読める" do
    visit admin_annotation_path(@word)

    # 閉じている間は定義文は見えない(チップの特徴名は見えている)
    assert_no_text "無い音が間に加わる"

    open_details ".ann-glossary"
    assert_text "無い音が間に加わる"
    assert_text "まんなか"
  end

  test "「提案を反映」で意味・ジャンル・属性がフォームに入る" do
    visit admin_annotation_path(@word)
    # JS の読み込み完了(=ページが落ち着くの)を待ってからクリックする
    wait_for_stimulus "genre-picker"

    assert_selector ".ann-proposal", text: "立項 5/5"

    # 反映後は解決済みジャンルが現在パス表示になる(画面更新の完了シグナル)
    click_expecting(expect_css: ".ann-genre__current", text: "小説", wait: 10) do
      find(".ann-proposal a", text: I18n.t("admin.annotations.proposal.apply"))
    end
    # 意味・品詞・語種・別表記もプレフィルされている(フォーム初期値のみで未保存)
    assert_includes find(".js-meaning").value, "谷川流"
    assert find("input[type=radio][value='#{parts_of_speech(:noun).id}']", visible: false).checked?
    assert find("input[type=checkbox][value='#{word_origins(:wago).id}']", visible: false).checked?
    assert_selector "input[value='ハルヒ']"
    assert_nil word_senses(:pending).reload.genre_id
  end

  # 同じ文字列が繰り返す語で、該当部分の「出現位置」が保存されること(target_start)。
  # 繰り返しの2つ目を選び、その位置(先頭からのオフセット)が記録されるのを担保する。
  test "特徴の該当部分に繰り返しの2つ目の出現位置が保存される" do
    word = Word.create!(surface: "びしょびしょの父")   # びしょ が2回出現(位置0と3)
    sense = word.word_senses.create!(reading: "ビショビショノチチ")
    feature = linguistic_features(:rendaku)

    visit admin_annotation_path(word)
    wait_for_stimulus "nested-form"             # 遅延読み込み完了を待ってから追加ボタンを押す
    # 追加は冪等でない(押すたびに行が増える)ので、ヘッドレスで取りこぼしにくい JS クリックで1回だけ足す。
    add_button = find(".ann-features button.ann-addrow", text: I18n.t("admin.annotations.add_feature"))
    execute_script("arguments[0].click()", add_button)
    assert_selector ".ann-feature .ann-cell", wait: 10   # feature-range が接続しストリップが描画された

    within all(".ann-feature").last do
      # 特徴のラジオを選ぶ(ネイティブクリックの取りこぼしを避けて JS で選択・change 発火)。
      radio = find("input[type=radio][value='#{feature.id}']", visible: false)
      execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", radio)
      # tap ごとにストリップが再描画されセル参照が stale になるので都度引き直す。
      # セルのネイティブクリックはヘッドレスで取りこぼすため JS クリックで確実に発火させる。
      surface = ".ann-strip:not(.ann-strip--reading) .ann-cell"
      reading = ".ann-strip--reading .ann-cell"
      tap_cell = ->(css, i) { execute_script("arguments[0].click()", all(css)[i]) }
      tap_cell.call(surface, 3)   # 単語: 2つ目の「びしょ」始点(位置3)
      tap_cell.call(surface, 5)   # 終点(位置5)
      tap_cell.call(reading, 0)   # 読み: 「ビショ」始点
      tap_cell.call(reading, 2)   # 終点
      # 隠しフィールドに単語側の出現位置(先頭からのオフセット)が入る
      assert_equal "3", find("input[name$='[target_start]']", visible: false).value
    end

    submit = find("input[type=submit][value='#{I18n.t("admin.annotations.save_next")}']")
    execute_script("arguments[0].click()", submit)

    # 保存された特徴が「びしょ / 位置3」で記録されている
    assert wait_until { word.reload.annotated_at.present? }
    saved = sense.word_sense_features.find_by(linguistic_feature: feature, target: "びしょ")
    assert_not_nil saved
    assert_equal 3, saved.target_start
    assert_equal "ビショ", saved.target_reading
  end

  private

  # チップの input は視覚的に隠れているため、ネイティブクリックに頼らず
  # 選択して change を発火させる(ヘッドレスでの取りこぼしを避ける)。
  def choose_hidden_input(selector)
    input = find(selector, visible: false)
    execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", input)
  end
end
