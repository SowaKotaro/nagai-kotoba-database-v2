require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  test "検索ページは未認証で開ける" do
    get search_path
    assert_response :success
  end

  test "結果は単語一覧(entry_row)で表示される" do
    get search_path
    assert_response :success
    assert_select ".search-results__count"
    assert_select "a.entry-row__surface"
  end

  # --- 各条件(結果は単語単位) ---
  test "先頭文字(50音・複数OR)で絞り込める" do
    get search_path, params: { first_char: [ word_senses(:curry).first_char ] }
    assert_response :success
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder)), count: 0
  end

  test "末尾文字で絞り込める" do
    get search_path, params: { last_char: [ word_senses(:curry).last_char ] }
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
  end

  test "キーワード(q)で絞り込める" do
    get search_path, params: { q: "カレー" }
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder)), count: 0
  end

  test "エンティティ種別(複数選択)で絞り込める" do
    get search_path, params: { entity_type_id: [ entity_types(:book_title).id ] }
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
    assert_select "a.entry-row__surface[href=?]", word_path(words(:curry)), count: 0
  end

  test "ジャンル階層(大)で絞り込める" do
    get search_path, params: { genre_id: genres(:large_literature).id }
    assert_select "a.entry-row__surface[href=?]", word_path(words(:abc_murder))
  end

  test "一致が無いときはメッセージを表示する" do
    get search_path, params: { first_char: [ "ヲ" ] }
    assert_response :success
    assert_select "p", text: I18n.t("searches.empty")
    assert_select ".search-results__count", text: I18n.t("searches.result_count", count: 0)
  end

  test "適用中の検索条件がチップで表示される" do
    get search_path, params: { q: "カレー" }
    assert_select ".condition-chip__value", text: "カレー"
  end

  test "page パラメータを付けても開ける" do
    get search_path, params: { page: 2 }
    assert_response :success
  end

  # --- 簡素検索(キーワードのみ・単語単位) ---
  test "簡素検索は未認証で開ける" do
    get simple_search_path
    assert_response :success
  end

  test "キーワード未入力なら入力を促す" do
    get simple_search_path
    assert_select "p", text: I18n.t("searches.simple.prompt")
  end

  test "簡素検索は表層形の部分一致で単語を返す" do
    get simple_search_path, params: { q: "殺人" }
    assert_response :success
    assert_select ".entry-row__surface", text: words(:abc_murder).surface
    assert_select ".entry-row__surface", text: words(:curry).surface, count: 0
  end

  test "簡素検索は読みの部分一致でも返す" do
    get simple_search_path, params: { q: "カレー" }
    assert_select ".entry-row__surface", text: words(:curry).surface
  end

  test "簡素検索は未注釈語を返さない" do
    get simple_search_path, params: { q: "涼宮ハルヒ" }
    assert_response :success
    assert_select ".entry-row__surface", text: words(:pending_haruhi).surface, count: 0
    assert_select "p", text: I18n.t("searches.simple.empty", q: "涼宮ハルヒ")
  end

  test "簡素検索から詳細検索への導線がある" do
    get simple_search_path, params: { q: "殺人" }
    assert_select "a.search-switch, .search-switch a", text: I18n.t("searches.simple.to_advanced")
  end
end
