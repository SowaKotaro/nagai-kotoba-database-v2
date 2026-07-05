require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  test "検索ページは未認証で開ける" do
    get search_path
    assert_response :success
  end

  test "結果は表示せず、検索フォームのみを描画する" do
    get search_path
    assert_response :success
    assert_select "form.search-form"
    assert_select ".entry-list", count: 0
  end

  # --- 検索実行(送信)は単語一覧へのリダイレクト ---
  test "検索を実行すると空条件を除いて単語一覧へリダイレクトする" do
    get search_path, params: { commit: I18n.t("searches.submit"), q: "カレー",
                               rhythm_pattern: "", char_type_pattern: "",
                               first_char: [ "カ" ], last_char: [] }
    assert_redirected_to words_path(q: "カレー", first_char: [ "カ" ])
  end

  test "ジャンル(複数選択)も単語一覧へ引き継がれる" do
    get search_path, params: { commit: I18n.t("searches.submit"),
                               genre_id: [ genres(:large_literature).id.to_s ] }
    assert_redirected_to words_path(genre_id: [ genres(:large_literature).id ])
  end

  test "commit なし(リンクからの遷移)はリダイレクトせずフォームに条件を反映する" do
    get search_path, params: { q: "カレー" }
    assert_response :success
    assert_select "input#q[value=?]", "カレー"
  end

  test "文字タイプ列の入力キー(あ/ア/漢/A/@)が表示される" do
    get search_path
    %w[あ ア 漢 A @].each do |char|
      assert_select "button.char-type-key[data-char-type-char-param=?]", char, text: char
    end
  end

  test "選択したジャンルの直下グループだけが展開されて描画される" do
    get search_path, params: { genre_id: [ genres(:large_literature).id ] }
    # 大「文学」を選択 → 中分類グループが表示、中「日本文学」未選択なので小分類グループは hidden。
    assert_select ".genre-filter__group[data-parent=?]:not([hidden])", genres(:large_literature).id.to_s
    assert_select ".genre-filter__group[data-parent=?][hidden]", genres(:medium_japanese).id.to_s
  end
end
