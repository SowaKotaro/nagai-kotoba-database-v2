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

  test "文字種の入力キー(あ/ア/漢/1/A/a/@)が表示される" do
    get search_path
    %w[あ ア 漢 1 A a @].each do |char|
      assert_select "button.char-type-key[data-char-type-char-param=?]", char, text: char
    end
  end

  test "文字種の切替アイコン(Aa/ab)が既定=厳密(点灯)で表示される" do
    get search_path
    # 既定は完全一致・大文字小文字を区別 → どちらのアイコンも点灯(aria-pressed=true)
    assert_select "button.char-type-flag__btn[aria-pressed=true]", count: 2
    # 緩い側のときだけ hidden に "1"。既定は厳密なので空
    assert_select "input[type=hidden][name=char_type_partial][value=?]", ""
    assert_select "input[type=hidden][name=char_type_ignore_case][value=?]", ""
  end

  test "文字種の切替アイコンは指定に応じて消灯し hidden に反映される" do
    get search_path, params: { char_type_pattern: "漢", char_type_partial: "1", char_type_ignore_case: "1" }
    assert_select "button.char-type-flag__btn[aria-pressed=false]", count: 2
    assert_select "input[type=hidden][name=char_type_partial][value=?]", "1"
    assert_select "input[type=hidden][name=char_type_ignore_case][value=?]", "1"
  end

  test "文字種の区別トグルも単語一覧へ引き継がれる" do
    get search_path, params: { commit: I18n.t("searches.submit"),
                               char_type_pattern: "漢漢", char_type_partial: "1",
                               char_type_ignore_case: "1" }
    assert_redirected_to words_path(char_type_pattern: "漢漢",
                                    char_type_partial: "1", char_type_ignore_case: "1")
  end

  test "文字種は削除ボタンとコンソール表示を持ち、手入力の text 欄は無い" do
    get search_path
    assert_select "button.char-type-key--backspace[data-action=?]", "char-type#remove"
    # 送信値は hidden、組み立て表示はコンソール(display ターゲット)
    assert_select "input[type=hidden]#char_type_pattern"
    assert_select ".char-type-display [data-char-type-target=display]"
    # 手入力できる text 欄は無い(ボタン専用=バリデーション兼用)
    assert_select "input[type=text]#char_type_pattern", count: 0
  end

  test "語種フィルタ(check_chips)が表示される" do
    get search_path
    word_origins(:kango, :eigo).each do |origin|
      assert_select "input[type=checkbox][name=?][value=?]", "word_origin_id[]", origin.id.to_s
    end
  end

  test "母音パターン検索の入力欄が表示される" do
    get search_path
    assert_select "input#vowel_reading"
    assert_select ".field-hint", text: I18n.t("searches.vowel_pattern_hint")
  end

  test "語種(複数選択)も単語一覧へ引き継がれる" do
    get search_path, params: { commit: I18n.t("searches.submit"),
                               word_origin_id: [ word_origins(:kango).id.to_s ] }
    assert_redirected_to words_path(word_origin_id: [ word_origins(:kango).id ])
  end

  test "ジャンルの折り畳みは選択なしではすべて畳まれている" do
    get search_path
    assert_select "details.genre-fold", minimum: 1
    assert_select "details.genre-fold[open]", count: 0
    # 大分類チップは「◯◯ 全体」のラベルで出る
    assert_select ".check-chip__face", text: I18n.t("searches.whole_genre", name: genres(:large_literature).name)
  end

  test "選択したジャンルを含む折り畳みは開いた状態で描画され、選択数が summary に出る" do
    get search_path, params: { genre_id: [ genres(:small_novel).id ] }
    # 小「小説」を選択 → その枝(大「文学」・中「日本文学」)の折り畳みが両方 open
    assert_select "details.genre-fold[open]", count: 2
    assert_select "details.genre-fold[open] .genre-fold__count", text: "1", count: 2
    assert_select "input[type=checkbox][name=?][value=?][checked]", "genre_id[]", genres(:small_novel).id.to_s
  end
end
