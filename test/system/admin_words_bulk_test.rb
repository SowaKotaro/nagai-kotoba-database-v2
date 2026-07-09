require "application_system_test_case"

# 単語管理一覧の一括アノテーション(Issue 37)の実機挙動。
# 全選択(check-all)とテーブル外フォームへの form 属性紐づけはブラウザでしか検証できない。
class AdminWordsBulkTest < ApplicationSystemTestCase
  test "全選択して共通属性を一括適用できる" do
    system_sign_in
    visit admin_words_path
    # 一括フォーム内の genre-picker も接続を待つ(接続時に「+ 追加」を差し込むため、
    # 待たないとレイアウトシフトとクリックが競合する)
    wait_for_stimulus "check-all"
    wait_for_stimulus "genre-picker"

    # 一括適用パネルを開き、エンティティ「書籍名」を選ぶ
    open_details ".bulk-annotation"
    click_expecting(expect_css: "#bulk-annotation-form input[value='#{entity_types(:book_title).id}']:checked",
                    visible: false) do
      find("#bulk-annotation-form label.ann-chip", text: entity_types(:book_title).name)
    end

    # ヘッダの全選択で表示中の行がすべてチェックされる
    assert_selector "tbody input[type=checkbox]", count: Word.count
    click_expecting(expect_css: "tbody input[type=checkbox]:checked", count: Word.count) do
      find("thead input[type=checkbox]")
    end

    # 送信して confirm を承認する。ダイアログは必ず出る(turbo_confirm)ので、
    # 出なければ accept_confirm が失敗し、送信が中止されたことに気づける。
    # 適用の成否は DB で判定する(送信後の描画タイミングはこの環境では不安定なため)。
    sense = word_senses(:pending)
    book_title_id = entity_types(:book_title).id
    submit = find("input[type=submit][value='#{I18n.t("admin.bulk_annotations.submit")}']")
    page.scroll_to(submit, align: :center)
    accept_confirm(I18n.t("admin.bulk_annotations.confirm")) { submit.click }
    assert wait_until { sense.reload.entity_type_id == book_title_id }, "一括適用が反映されませんでした"

    # 全語が単一語義なので全件に適用される(他の語も確認)
    assert_equal book_title_id, word_senses(:curry).reload.entity_type_id
    # 注釈済みフラグは既定 OFF なので立たない
    assert_nil words(:pending_haruhi).reload.annotated_at
  end
end
