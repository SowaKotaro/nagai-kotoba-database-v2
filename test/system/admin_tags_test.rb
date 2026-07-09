require "application_system_test_case"

# タグ統括管理の実機スモーク(ハブ → 種別一覧 → 編集画面への遷移、ジャンルの階層表示)。
# 実際の更新・削除の挙動はコントローラテストで担保する。ここでは画面の描画と導線を確認する。
class AdminTagsTest < ApplicationSystemTestCase
  test "ハブから種別一覧・編集画面へ遷移でき、名前が引き継がれる" do
    system_sign_in
    visit admin_tags_path
    assert_selector "h1", text: "タグ管理"

    # ハブのカード → 種別一覧。ネイティブクリック取りこぼし対策に click_expecting を使う。
    click_expecting(expect_css: ".tag-table") { find("a.admin-card", text: "エンティティタイプ") }
    assert_selector "h1", text: "エンティティタイプ"

    # 名前リンク → 編集画面。現在の名前が入力欄に引き継がれている。
    click_expecting(expect_css: "#tag_name") { find("td a", text: "書籍名") }
    assert_selector "h1", text: "エンティティタイプの編集"
    assert_equal "書籍名", find("#tag_name").value
  end

  test "ジャンルは階層(木)順にインデントして並ぶ" do
    system_sign_in
    visit admin_tag_kind_path("genres")

    # fixtures は 文学 › 日本文学 › 小説 の一系統。深さ優先で大→中→小の順に並ぶ。
    names = all(".tag-table tbody td.tag-table__name").map { |cell| cell.text.strip }
    assert_equal %w[文学 日本文学 小説], names

    # 中・小分類はインデント用のクラスが付く。
    assert_selector "td.tag-table__name--large", text: "文学"
    assert_selector "td.tag-table__name--medium", text: "日本文学"
    assert_selector "td.tag-table__name--small", text: "小説"
  end

  test "使用状況に応じて削除ボタンの有無が変わる" do
    # 実削除の挙動はコントローラテストで担保。ここでは一覧の描画(削除可否の出し分け)を確認する。
    system_sign_in
    visit admin_tag_kind_path("entity_types")

    # 人名(未使用)の行には削除ボタンが出る。
    within find("tr", text: "人名") do
      assert_button "削除"
    end

    # 書籍名(語義に付与済み)の行は「使用中」表示で削除ボタンが出ない。
    within find("tr", text: "書籍名") do
      assert_no_button "削除"
      assert_text "使用中"
    end
  end
end
