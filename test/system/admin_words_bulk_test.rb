require "application_system_test_case"

# 単語の修正の一覧の、まとめて付ける(Issue 37)・まとめて外す(Issue 108)の実機挙動。
# 全選択(check-all)・テーブル外フォームへの form 属性の紐づけ・送信ボタンの formaction はブラウザでしか検証できない。
class AdminWordsBulkTest < ApplicationSystemTestCase
  ANNOTATION_PANEL = "#bulk-form > details:nth-of-type(1)"
  DETACHMENT_PANEL = "#bulk-form > details:nth-of-type(2)"

  test "全選択して共通属性をまとめて付け、同じ選択のまま外せる。外す特徴は選択した語に共通するものだけが出る" do
    system_sign_in
    visit admin_words_path
    # 一括フォーム内の genre-picker も接続を待つ(接続時に「+ 追加」を差し込むため、
    # 待たないとレイアウトシフトとクリックが競合する)
    wait_for_stimulus "check-all"
    wait_for_stimulus "genre-picker"

    # まとめて付けるパネルを開き、エンティティ「書籍名」を選ぶ
    book_title = entity_types(:book_title)
    open_details ANNOTATION_PANEL
    click_expecting(expect_css: "#{ANNOTATION_PANEL} input[value='#{book_title.id}']:checked", visible: false) do
      find("#{ANNOTATION_PANEL} label.ann-chip", text: book_title.name)
    end
    select_all_rows

    # 送信して confirm を承認する。confirm は必ず呼ばれる(turbo_confirm)ので、
    # 呼ばれなければ click_accepting_confirm が失敗し、送信が中止されたことに気づける。
    # 適用の成否は DB で判定する(送信後の描画タイミングはこの環境では不安定なため)。
    sense = word_senses(:pending)
    click_accepting_confirm(I18n.t("admin.bulk_annotations.confirm")) do
      find("input[type=submit][value='#{I18n.t("admin.bulk_annotations.submit")}']")
    end
    assert wait_until { sense.reload.entity_type_id == book_title.id }, "まとめて付けたのが反映されませんでした"
    # 全語が単一語義なので全件に適用される(他の語も確認)。注釈済みフラグは既定 OFF なので立たない
    assert_equal book_title.id, word_senses(:curry).reload.entity_type_id
    assert_nil words(:pending_haruhi).reload.annotated_at

    # 戻った一覧で、まとめて外すパネルから同じエンティティを外す(送信ボタンの formaction で送り先が変わる)
    assert_selector "#flash", text: /適用しました/
    wait_for_stimulus "check-all"
    wait_for_stimulus "bulk-detachment-features"
    open_details DETACHMENT_PANEL
    assert_shared_feature_chips [], I18n.t("admin.bulk_detachments.features_none_selected")

    # 特徴(連濁・重箱読み)が付いているのは ABC殺人事件だけ。その語だけを選ぶと両方が出て、
    # 全選択すると(ほかの語に付いていないので)どちらも消える
    murder = words(:abc_murder)
    click_expecting(expect_css: "tbody input[value='#{murder.id}']:checked") { find("tbody input[value='#{murder.id}']") }
    assert_shared_feature_chips %i[rendaku jubako], I18n.t("admin.bulk_detachments.features_hint")
    select_all_rows
    assert_shared_feature_chips [], I18n.t("admin.bulk_detachments.features_none_shared")

    choose_hidden_input "#{DETACHMENT_PANEL} input[name='bulk_detachment[entity_type_id]'][value='#{book_title.id}']"
    click_accepting_confirm(I18n.t("admin.bulk_detachments.confirm")) do
      find("input[type=submit][value='#{I18n.t("admin.bulk_detachments.submit")}']")
    end
    assert wait_until { sense.reload.entity_type_id.nil? }, "まとめて外したのが反映されませんでした"
    assert_nil word_senses(:curry).reload.entity_type_id
  end

  private

  # まとめて外すパネルに見えている特徴のチップが、指定した特徴(フィクスチャ名)だけで、案内の文言が出ている
  def assert_shared_feature_chips(feature_names, status)
    names = feature_names.map { |name| linguistic_features(name).name }
    chips = "#{DETACHMENT_PANEL} label[data-bulk-detachment-features-target=chip]"
    assert_selector chips, count: names.size
    names.each { |name| assert_selector chips, text: name }
    assert_selector "#{DETACHMENT_PANEL} [data-bulk-detachment-features-target=status]", text: status
  end

  # ヘッダの全選択で、表示中の行がすべてチェックされる
  def select_all_rows
    assert_selector "tbody input[type=checkbox]", count: Word.count
    click_expecting(expect_css: "tbody input[type=checkbox]:checked", count: Word.count) do
      find("thead input[type=checkbox]")
    end
  end
end
