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
end
