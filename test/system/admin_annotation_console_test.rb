require "application_system_test_case"

# アノテーション・コンソールの実機挙動。統合テストでは動かない Stimulus
# (ジャンルの段階表示とその場追加・語義カードの完了表示・特徴の範囲タップ・公開前の確認)をブラウザで担保する。
# サーバが描くもの(提案の反映・用語解説・再調査用 JSON)は Admin::AnnotationsControllerTest で見る。
class AdminAnnotationConsoleTest < ApplicationSystemTestCase
  setup do
    @word = words(:pending_haruhi)
    system_sign_in
  end

  # スマホ幅では最下部のアクションバーが2〜3行に折り返す。「保存して次へ」が行の途中
  # (画面下端の中ほど)に来ると、iOS の画面下端ジェスチャ(Apple Intelligence の呼び出し)と
  # 近くて押しづらいため、折り返しても必ず右端に置く。
  test "スマホ幅でも保存ボタンは画面の右端に置く" do
    resize_window_to(402, 874)
    visit admin_annotation_path(@word)
    assert_selector ".ann-actionbar"

    edges = page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector(".ann-actionbar");
        const save = bar.querySelector(".btn--primary");
        return { bar: bar.getBoundingClientRect().right, save: save.getBoundingClientRect().right };
      })()
    JS
    assert_in_delta edges["bar"], edges["save"], 1, "保存ボタンがアクションバーの右端に寄っていない"
  ensure
    resize_window_to(*ApplicationSystemTestCase::DEFAULT_SCREEN_SIZE)
  end

  test "ジャンルを大→中→小と選んで保存すると、公開前の確認を経て注釈済みになり次の語へ進む" do
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

    # 最低限(読み・語種・ジャンル・品詞・エンティティ)が揃っていない語を公開しようとすると
    # 確認が挟まる(未完了公開の事故ガード・Issue 68)。承認して公開し、次の未注釈(bermuda)へ進む。
    click_accepting_confirm(I18n.t("admin.annotations.publish_incomplete_confirm")) do
      find("input[type=submit][value='#{I18n.t("admin.annotations.save_next")}']")
    end
    assert_selector "h1.ann-word", text: words(:pending_bermuda).surface, wait: 10
    # 保存した語は注釈済みになり、選んだジャンルが付いている
    assert wait_until { @word.reload.annotated_at.present? }
    assert_equal genres(:small_novel).id, word_senses(:pending).reload.genre_id
  end

  # 保留は公開しないので、公開前の確認(publish-guard)を通さずに送る。
  test "保留にすると確認なしで保留になり、キューから外れて次の未対応へ進む" do
    visit admin_annotation_path(@word)
    wait_for_stimulus "genre-picker"

    # 「保留にして次へ」は同じフォームを hold へ送る(formaction)。次の未対応(bermuda)へ進む
    click_expecting(expect_css: "h1.ann-word", text: words(:pending_bermuda).surface, wait: 10) do
      find("input[type=submit][value='#{I18n.t("admin.annotations.hold")}']")
    end

    # 保留になり、公開時刻は付かない
    assert @word.reload.annotation_on_hold?
    assert_nil @word.annotated_at
  end

  # 最低限のアノテーション項目(読み・語種・ジャンル・品詞・エンティティ)が揃うと
  # 語義カードの枠が完了(is-complete)になる。保存できるかどうかとは無関係の目印。
  test "最低限の項目が揃うと語義カードが完了表示になり、ジャンルが中分類止まりや読みが欠けると外れる" do
    visit admin_annotation_path(@word)
    wait_for_stimulus "sense-completeness"

    # 初期状態は読みだけ。語種・品詞・エンティティを選んでも、ジャンルが未設定なので完了にならない
    assert_no_selector ".ann-sense.is-complete"
    choose_hidden_input "input[type=checkbox][value='#{word_origins(:wago).id}']"
    choose_hidden_input "input[type=radio][value='#{parts_of_speech(:noun).id}']"
    choose_hidden_input "input[type=radio][value='#{entity_types(:book_title).id}']"
    assert_no_selector ".ann-sense.is-complete"

    within ".ann-genre" do
      click_expecting(expect_css: ".ann-chip", text: "日本文学") { find("button.ann-chip", exact_text: "文学") }
      click_expecting(expect_css: ".ann-chip", text: "小説") { find("button.ann-chip", exact_text: "日本文学") }
    end
    # 中分類止まりでは genre_id は空のままで、完了にならない
    assert_equal "", find(".js-genre-value", visible: false).value
    assert_no_selector ".ann-sense.is-complete"

    within ".ann-genre" do
      click_expecting(expect_css: ".ann-chip.is-on", text: "小説") { find("button.ann-chip", exact_text: "小説") }
    end
    assert_selector ".ann-sense.is-complete"

    # 読みを消せば完了表示は外れる
    find(".ann-reading").set("")
    assert_no_selector ".ann-sense.is-complete"
  end

  test "提案の小分類が未登録でも、大・中まで一致すればピッカーがそこまで開く" do
    # 小分類「私小説」は木に無い。大「文学」・中「日本文学」までは既存
    annotation_proposals(:haruhi_proposal).update!(payload: { "genre_path" => %w[文学 日本文学 私小説] })

    visit admin_annotation_path(@word, apply_proposal: 1)
    wait_for_stimulus "genre-picker"

    within ".ann-genre" do
      # 大・中が選択状態(is-on)になり、小分類の選択肢(小説)まで開いている
      assert_selector ".ann-chip.is-on", text: "文学"
      assert_selector ".ann-chip.is-on", text: "日本文学"
      assert_selector "[data-genre-picker-target='smallLevel'] .ann-chip", text: "小説"
    end
    # 小分類は未確定なので genre_id は空(その場追加 or 既存選択で確定させる運用)
    assert_equal "", find(".js-genre-value", visible: false).value
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
      choose_hidden_input "input[type=radio][value='#{feature.id}']"
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
    # この語も最低限が未完了なので保存に確認が挟まる(Issue 68)。承認して公開する。
    page.execute_script("window.confirm = () => true; arguments[0].click()", submit)

    # 保存された特徴が「びしょ / 位置3」で記録されている
    assert wait_until { word.reload.annotated_at.present? }
    saved = sense.word_sense_features.find_by(linguistic_feature: feature, target: "びしょ")
    assert_not_nil saved
    assert_equal 3, saved.target_start
    assert_equal "ビショ", saved.target_reading
  end

  # ジャンルの「その場追加」。入力して Enter を押したのに何も起きない(入力欄が残る)
  # 状態を作らないことを担保する。
  #   - 既にある名前を入れたら、二重に作らず既存のチップを選ぶ
  #   - 失敗したら理由が出る(黙って握りつぶさない)
  test "ジャンルのその場追加で既にある名前を入れると、既存が選ばれて入力欄が閉じる" do
    visit admin_annotation_path(@word)
    wait_for_stimulus "genre-picker"

    within ".ann-genre" do
      click_expecting(expect_css: ".ann-chip", text: "日本文学") { find("button.ann-chip", exact_text: "文学") }

      # 中分類の「＋追加」に、既にある「日本文学」を入れる
      within ".js-genre-medium" do
        click_via_js(expect_css: ".ann-add__input:not([hidden])") { find("button.ann-add__btn") }
        assert_no_difference -> { Genre.count } do
          find(".ann-add__input").send_keys("日本文学", :enter)
          assert_selector ".ann-add__msg", text: I18n.t("admin.inline_add.client.selected_existing")
        end
        # 入力欄は閉じ、既存のチップが選ばれている(＝小分類が開く)
        assert_no_selector ".ann-add__input:not([hidden])"
      end
      assert_selector ".js-genre-medium .ann-chip.is-on", exact_text: "日本文学"
      assert_selector ".js-genre-small .ann-chip", text: "小説"
    end
  end

  # 語義の複製は DOM を outerHTML で写すため、JS で結び付けたハンドラが付いてこない。
  # 複製された語義でも「その場追加」が動くこと(押しても何も起きない状態にならないこと)。
  test "語義を複製しても、ジャンルの大分類の「その場追加」が使える" do
    visit admin_annotation_path(@word)
    wait_for_stimulus "sense-cloner"
    wait_for_stimulus "genre-picker"

    click_expecting(expect_css: ".js-sense", count: 2) { find("button.ann-add-sense") }

    within all(".js-sense").last do
      within ".js-genre-large" do
        click_via_js(expect_css: ".ann-add__input:not([hidden])") { find("button.ann-add__btn") }
        assert_difference -> { Genre.large.count } => 1 do
          find(".ann-add__input").send_keys("架空の大分類", :enter)
          assert_selector ".ann-chip.is-on", exact_text: "架空の大分類"
        end
      end
      # 追加した大分類が選ばれ、中分類の選択肢が開く
      assert_selector ".js-genre-medium .ann-add__btn"
    end
  end
end
