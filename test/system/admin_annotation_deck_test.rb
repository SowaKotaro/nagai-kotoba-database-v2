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

  # 提案欄の「＋作成」(Issue 66 のデッキ版)。デッキのフォームごと送って画面を組み直すので、
  # 「作ったマスタが選択済みで入る」「他のカードを含む入力が消えない」「見ていたカードに戻る」
  # の3点を実機で見る(サーバ側の組み直しは統合テストで担保済み)。
  test "提案の新設候補をその場で作ると、入力と現在地を保ったままカードに入る" do
    # 提案キュー(2枚)を作る。1枚目にマスタ未登録のエンティティを提案させる
    annotation_proposals(:haruhi_proposal).update!(status: :pending, payload: {
      "senses" => [ { "meaning" => "架空の意味。", "entity_type" => "架空種別" } ]
    })
    AnnotationProposal.create!(word: @bermuda, status: :pending,
                               payload: { "senses" => [ { "meaning" => "海域の名。" } ] })
    visit admin_annotation_deck_path(proposed: 1)
    wait_for_stimulus "deck"

    # 別のカード(提案欄を持たない方)に入力しておく。組み直しで消えないことを見る
    fill_in "deck[#{@bermuda.id}][word_senses_attributes][0][meaning]", with: "消えては困る入力"

    # 「＋作成」があるカードへ送ってから押す(組み直しでそのカードに戻ることを見る)
    create_button = -> { find("input[type=submit][value='#{I18n.t("admin.annotations.proposal.create_master")}']") }
    position = create_button.call.find(:xpath, "ancestor::article[@data-deck-target='card']")["data-index"].to_i + 1
    click_expecting(expect_css: "[data-deck-target='position']", text: position.to_s) do
      find(".deck-dot[data-index='#{position - 1}']")
    end

    click_expecting(expect_css: ".ann-chip", text: "架空種別", &create_button)

    # 作ったエンティティが、そのカードで選択済みになっている(チップの input は視覚的に隠れている)
    created = EntityType.find_by!(name: "架空種別")
    selector = ".deck-card[data-index='#{position - 1}'] input[type=radio][value='#{created.id}']"
    assert_selector selector, visible: false
    assert page.evaluate_script("document.querySelector(#{selector.to_json}).checked"),
           "作ったエンティティが選択済みになっていない"
    assert_field "deck[#{@bermuda.id}][word_senses_attributes][0][meaning]", with: "消えては困る入力"
    # 見ていたカードに戻る
    assert_selector "[data-deck-target='position']", text: position.to_s
  end

  # チップの input は視覚的に隠れているため、ネイティブクリックに頼らず
  # 選択して change を発火させる(ヘッドレスでの取りこぼしを避ける)。
  def choose_hidden_input(selector)
    input = find(selector, visible: false)
    execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", input)
  end
end
