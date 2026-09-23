require "test_helper"

# ファセット付き一覧のインデックス方針(Issue 17・80・81)の結合テスト。
# index させる面・させない面・存在しない面(404)・canonical の向き先を固定する。
class FacetIndexingTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "素の一覧(1ページ目)は index で canonical は /words" do
    get words_path
    assert_response :success
    assert_select "meta[name=robots]", count: 0
    assert_select "h1.page-title", text: I18n.t("words.index.title")
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words"
  end

  # 値域が有限で、それ自体が検索需要になる面(「読みが15文字の長い言葉」など)。
  # 統計・索引から常時リンクしているので index し、見出し・title・description を面ごとに作る。
  test "単一ファセットの1ページ目は index で、見出し・title・description・canonical を面ごとに持つ" do
    genre = genres(:large_literature)
    feature = linguistic_features(:rendaku)
    {
      { genre_id: genre.id } => [ "文学の長い言葉", "/words?genre_id=#{genre.id}" ],
      { first_char: "カ" } => [ "「カ」から始まる長い言葉", "/words?first_char=%E3%82%AB" ],
      { last_char: "ン" } => [ "「ン」で終わる長い言葉", "/words?last_char=%E3%83%B3" ],
      { reading_length: 7 } => [ "読みが7文字の長い言葉", "/words?reading_length=7" ],
      { mora_count: 7 } => [ "7モーラの長い言葉", "/words?mora_count=7" ],
      { linguistic_feature_id: feature.id } => [ "#{feature.name}の長い言葉", "/words?linguistic_feature_id=#{feature.id}" ]
    }.each do |params, (heading, canonical)|
      get words_path(params)
      assert_response :success
      assert_select "meta[name=robots]", { count: 0 }, "#{params} が noindex になっている"
      assert_select "h1.page-title", text: heading
      assert_select "title", text: "#{heading} | #{I18n.t('layouts.brand')}"
      assert_select "meta[name=description][content=?]", I18n.t("words.index.facet_description", label: heading)
      assert_select "link[rel=canonical][href=?]", "#{HOST}#{canonical}"
      # 条件を引き継ぐ /search?... はファセットの数だけ増えるので、「検索条件を編集」はクロールさせない
      assert_select "a.active-facet__edit[rel=nofollow]", count: 1
    end
  end

  # 条件の組み合わせ・キーワード・範囲指定は値の取り方が無限にあり、内容も他の面と重なる。
  test "複数条件・キーワード・範囲指定・検索フォームは noindex,follow" do
    get words_path(genre_id: genres(:large_literature).id, first_char: "カ")
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "h1.page-title", text: I18n.t("words.index.title") # 見出しは既定のまま

    [ words_path(q: "カレー"), words_path(reading_length_min: 7), words_path(dakuten_min: 2), search_path ].each do |path|
      get path
      assert_response :success
      assert_select "meta[name=robots][content=?]", "noindex,follow", true, "#{path} が noindex,follow でない"
    end
  end

  # content_for は値を HTML エスケープして貯めるため、素通しするとクエリの & が &amp;amp; になり、
  # 「amp;page」という実在しないパラメータ名の URL が canonical に出る。
  test "2ページ目以降は noindex,follow で、canonical と og:url は page を含み & を二重エスケープしない" do
    get words_path(page: 2)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/words?page=2"

    get words_path(first_char: "カ", page: 2)
    # assert_select は実体参照を解いてから照合するので、ここで「& が1回だけエスケープされている」ことまで
    # 担保できる。二重エスケープの再発が一目で分かるよう、生の本文も直接見ておく
    canonical = "#{HOST}/words?first_char=%E3%82%AB&page=2"
    assert_select "link[rel=canonical][href=?]", canonical
    assert_select "meta[property='og:url'][content=?]", canonical
    assert_not_includes response.body, "&amp;amp;"
  end

  # --- noindex のページが他の URL を canonical に指さない ---
  #
  # noindex + 他 URL への canonical は、指し先へ noindex が伝播しうる組合せ。
  # かつて並び替えの canonical が一律 /words を指しており、シードの数だけ増えた
  # noindex ページ(実測 3,186 件)が揃ってサイトのハブを正規版に指名していた。

  test "並び替えは noindex だが canonical は自身を指し、既定の並びを明示しただけなら index のまま" do
    genre = genres(:large_literature)
    {
      words_path(sort: "length_desc") => "/words?sort=length_desc",
      # ファセット + 並び替えは両方を含む(素のファセット面を指さない)
      words_path(genre_id: genre.id, sort: "kana_asc") => "/words?genre_id=#{genre.id}&sort=kana_asc"
    }.each do |path, canonical|
      get path
      assert_response :success
      assert_select "meta[name=robots][content=?]", "noindex,follow"
      assert_select "link[rel=canonical][href=?]", "#{HOST}#{canonical}"
    end

    get words_path(sort: "created_desc")
    assert_select "meta[name=robots]", count: 0
  end

  # シャッフルは並び違いの重複でしかないので index せず、クロールもさせない。
  # シードは URL に載せない値なので、既知のシード付き URL も seed 抜きの1本を canonical にする。
  test "シャッフルは noindex,follow で、ボタンは nofollow、canonical は seed を含まない自身" do
    [ words_path(sort: "shuffle"), words_path(sort: "shuffle", seed: "abcd1234") ].each do |path|
      get path
      assert_response :success
      assert_select "meta[name=robots][content=?]", "noindex,follow"
      assert_select "link[rel=canonical][href=?]", "#{HOST}/words?sort=shuffle"
      assert_select ".entry-toolbar__shuffle[rel=nofollow]", count: 1
    end
  end

  # --- 元から存在しないページ ---
  #
  # 黙って無視すると、genre_id は絞り込みごと落ちて /words の完全な複製が、
  # 他の軸は中身の無い面が、それぞれ任意の数値ぶん index 可能な形で作れてしまう。

  test "実在しないマスタ id(数値でない値・複数選択の一部を含む)は 404" do
    [
      { genre_id: 999_999 },
      { linguistic_feature_id: 999_999 },
      { entity_type_id: 999_999 },
      { part_of_speech_id: "abc" },
      { genre_id: [ genres(:large_literature).id, 999_999 ] }
    ].each do |params|
      get words_path(params)
      assert_response :not_found, "#{params} が 404 にならない"
    end
  end

  test "実在する軸でも公開語が0件の面は noindex" do
    # モーラ数 12 の語義は未注釈のものしか無い(=公開0件)
    get words_path(mora_count: 12)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "h1.page-title", text: "12モーラの長い言葉"

    # 読みの文字数 99 は値だけが存在しない
    get words_path(reading_length: 99)
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end
end
