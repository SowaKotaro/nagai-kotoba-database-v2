require "application_system_test_case"

# アノテーション・デッキ(まとめてアノテーション)の実機挙動。
# 統合テストでは動かない部分(カード送り・完了の集計・1回の送信での複数語保存)を担保する。
class AdminAnnotationDeckTest < ApplicationSystemTestCase
  setup do
    @haruhi = words(:pending_haruhi)
    @bermuda = words(:pending_bermuda)
    # 提案キューへの自動誘導を外し、未対応2語がデッキに並ぶ状態にする
    annotation_proposals(:haruhi_proposal).applied!
    system_sign_in
  end

  test "矢印とドットでカードを送れる" do
    visit admin_annotation_deck_path
    wait_for_stimulus "deck"

    assert_selector ".deck-card", count: 2
    assert_selector "[data-deck-target='position']", text: "1"
    # 先頭では「前へ」が押せない
    assert find("[data-deck-target='prev']").disabled?

    click_expecting(expect_css: "[data-deck-target='position']", text: "2") do
      find("[data-deck-target='next']")
    end
    assert_selector ".deck-dot.is-on[data-index='1']"
    assert find("[data-deck-target='next']").disabled?

    # ドットで1枚目へ戻る
    click_expecting(expect_css: "[data-deck-target='position']", text: "1") do
      find(".deck-dot[data-index='0']")
    end
  end

  # スマホの横スワイプは scroll-snap(CSS)がスクロールを担い、JS は位置の追従だけを行う。
  # 実機のスワイプは再現しづらいので、トラックのスクロール = スワイプとみなして検証する。
  test "トラックを横スクロールすると現在地の表示が追従する" do
    visit admin_annotation_deck_path
    wait_for_stimulus "deck"

    execute_script(<<~JS)
      const track = document.querySelector("[data-deck-target='track']");
      const card = document.querySelectorAll("[data-deck-target='card']")[1];
      track.scrollLeft = card.offsetLeft;
      track.dispatchEvent(new Event("scroll"));
    JS
    assert_selector "[data-deck-target='position']", text: "2"
  end

  test "最低限の項目が揃うと完了数とドットに反映される" do
    visit admin_annotation_deck_path
    wait_for_stimulus "deck"

    assert_selector "[data-deck-target='complete']", text: "0"

    within first(".deck-card") do
      choose_hidden_input "input[type=checkbox][value='#{word_origins(:wago).id}']"
      choose_hidden_input "input[type=radio][value='#{parts_of_speech(:noun).id}']"
      choose_hidden_input "input[type=radio][value='#{entity_types(:book_title).id}']"
      within ".ann-genre" do
        click_expecting(expect_css: ".ann-chip", text: "日本文学") { find("button.ann-chip", exact_text: "文学") }
        click_expecting(expect_css: ".ann-chip", text: "小説") { find("button.ann-chip", exact_text: "日本文学") }
        click_expecting(expect_css: ".ann-chip.is-on", text: "小説") { find("button.ann-chip", exact_text: "小説") }
      end
      assert_selector ".ann-sense.is-complete"
    end

    # 1枚目だけ完了。ドットにも印が付く
    assert_selector "[data-deck-target='complete']", text: "1"
    assert_selector ".deck-dot.is-done[data-index='0']"
    assert_no_selector ".deck-dot.is-done[data-index='1']"
  end

  test "まとめて保存すると2語がいっぺんに注釈済みになる" do
    visit admin_annotation_deck_path
    wait_for_stimulus "publish-guard"

    # どちらも読みだけで未完了なので、公開前の確認が挟まる(1語コンソールと同じガード)
    click_accepting_confirm(I18n.t("admin.annotation_decks.publish_incomplete_confirm")) do
      find("input[type=submit][value='#{I18n.t("admin.annotation_decks.save_all", count: 2)}']")
    end

    assert_selector ".flash--notice", text: I18n.t("admin.annotation_decks.update.saved", count: 2), wait: 10
    assert wait_until { @haruhi.reload.annotated_at.present? && @bermuda.reload.annotated_at.present? }
  end

  # チップの input は視覚的に隠れているため、ネイティブクリックに頼らず
  # 選択して change を発火させる(ヘッドレスでの取りこぼしを避ける)。
  def choose_hidden_input(selector)
    input = find(selector, visible: false)
    execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", input)
  end
end
