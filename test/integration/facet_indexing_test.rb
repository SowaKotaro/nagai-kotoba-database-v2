require "test_helper"

# ファセット付き一覧のインデックス方針(Issue 17)の結合テスト。
class FacetIndexingTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "素の一覧(1ページ目)は index で canonical は /words" do
    get words_path
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: I18n.t("words.index.title")
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words"
  end

  test "単一ジャンルのファセット(1ページ目)は index + 動的見出し" do
    genre = genres(:large_literature)
    get words_path(genre_id: genre.id)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "文学の長い言葉"
    assert_select "title", text: "文学の長い言葉 | #{I18n.t('layouts.brand')}"
    assert_select "meta[name=description][content=?]",
      I18n.t("words.index.facet_description", label: "文学の長い言葉")
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?genre_id=#{genre.id}"
  end

  test "先頭文字の単一ファセットは index + 動的見出し" do
    get words_path(first_char: "カ")
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "「カ」から始まる長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?first_char=%E3%82%AB"
  end

  test "末尾文字の単一ファセットは index + 動的見出し" do
    get words_path(last_char: "ン")
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "「ン」で終わる長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?last_char=%E3%83%B3"
  end

  test "複数条件は noindex,follow で見出しは既定" do
    get words_path(genre_id: genres(:large_literature).id, first_char: "カ")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "h1.page-title", text: I18n.t("words.index.title")
  end

  test "キーワード検索は noindex,follow" do
    get words_path(q: "カレー")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  test "2ページ目以降は noindex,follow で canonical に page を含む" do
    get words_path(page: 2)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?page=2"
  end

  # 読みの文字数・モーラ数・言語的特徴は、値域が有限で「読みが15文字の長い言葉」のように
  # 本サイトの検索需要そのものになる面。統計・索引から常時リンクしているので index する。
  test "読みの文字数の単一ファセットは index + 動的見出し" do
    get words_path(reading_length: 7)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "読みが7文字の長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?reading_length=7"
  end

  test "モーラ数の単一ファセットは index + 動的見出し" do
    get words_path(mora_count: 7)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "7モーラの長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?mora_count=7"
  end

  test "言語的特徴の単一ファセットは index + 動的見出し" do
    feature = linguistic_features(:rendaku)
    get words_path(linguistic_feature_id: feature.id)
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: "#{feature.name}の長い言葉"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?linguistic_feature_id=#{feature.id}"
  end

  # 範囲指定は値の取り方が無限にあり、内容も他の面と重なるためインデックスしない。
  test "読みの長さの範囲指定は noindex,follow" do
    get words_path(reading_length_min: 7)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  # シャッフルは並び違いの重複でしかないので index せず、クロールもさせない。
  test "シャッフルは noindex,follow で、ボタンにも nofollow が付く" do
    get words_path(sort: "shuffle")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select ".entry-toolbar__shuffle[rel=nofollow]", count: 1
  end

  test "検索フォーム(/search)は noindex,follow" do
    get search_path
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  # 条件を引き継ぐ /search?... はファセットの数だけ増えるので、クロールさせない。
  test "「検索条件を編集」リンクは nofollow" do
    get words_path(genre_id: genres(:large_literature).id)
    assert_response :success
    assert_select "a.active-facet__edit[rel=nofollow]", count: 1
  end

  # --- 実在しないマスタ id は 404(元から存在しないページ) ---
  #
  # 黙って無視すると、genre_id は絞り込みごと落ちて /words の完全な複製が、
  # 他の軸は中身の無い面が、それぞれ任意の数値ぶん index 可能な形で作れてしまう。

  test "実在しないジャンル id は 404(/words の複製を作らせない)" do
    get words_path(genre_id: 999_999)
    assert_response :not_found
  end

  test "実在しない言語的特徴 id は 404" do
    get words_path(linguistic_feature_id: 999_999)
    assert_response :not_found
  end

  test "実在しないエンティティ id は 404" do
    get words_path(entity_type_id: 999_999)
    assert_response :not_found
  end

  test "数値でないマスタ id も 404" do
    get words_path(part_of_speech_id: "abc")
    assert_response :not_found
  end

  test "複数選択の一部だけ実在しなくても 404" do
    get words_path(genre_id: [ genres(:large_literature).id, 999_999 ])
    assert_response :not_found
  end

  # --- 中身が0件の面は index させない ---

  test "実在する軸でも公開語が0件なら noindex" do
    # モーラ数 12 の語義は未注釈のものしか無い(=公開0件)。
    get words_path(mora_count: 12)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "h1.page-title", text: "12モーラの長い言葉"
  end

  test "値だけが存在しない読みの文字数も noindex" do
    get words_path(reading_length: 99)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  # --- noindex のページが他の URL を canonical に指さない ---
  #
  # noindex + 他 URL への canonical は、指し先へ noindex が伝播しうる組合せ。
  # かつて並び替えの canonical が一律 /words を指しており、シードの数だけ増えた
  # noindex ページ(実測 3,186 件)が揃ってサイトのハブを正規版に指名していた。

  test "並び替えは noindex だが canonical は自身を指す" do
    get words_path(sort: "length_desc")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?sort=length_desc"
  end

  test "ファセット + 並び替えの canonical は両方を含む(素のファセット面を指さない)" do
    genre = genres(:large_literature)
    get words_path(genre_id: genre.id, sort: "kana_asc")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?genre_id=#{genre.id}&sort=kana_asc"
  end

  # シードは URL に載せない値なので、既知のシード付き URL は seed 抜きの1本に集約する。
  test "シード付きシャッフルの canonical は seed を含まない1本に寄る" do
    get words_path(sort: "shuffle", seed: "abcd1234")
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?sort=shuffle"
  end

  # --- canonical の二重エスケープ ---
  #
  # content_for は値を HTML エスケープして貯めるため、素通しするとクエリの & が
  # &amp;amp; になり、「amp;page」という実在しないパラメータ名の URL が canonical に出る。

  test "クエリが2つ以上の canonical が二重エスケープされない" do
    get words_path(first_char: "カ", page: 2)
    assert_response :success
    # assert_select は実体参照を解いてから照合するので、上の1行で「& が1回だけ
    # エスケープされている」ことまで担保できる。生の本文に &amp;amp; が出ていないことも
    # 直接見ておく(二重エスケープの再発は、ここだけを見れば分かる)。
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?first_char=%E3%82%AB&page=2"
    assert_not_includes response.body, "&amp;amp;"
  end

  test "og:url も canonical と同じ URL を出す" do
    get words_path(first_char: "カ", page: 2)
    assert_response :success
    assert_select "meta[property='og:url'][content=?]", "#{HOST}/words?first_char=%E3%82%AB&page=2"
  end
end
