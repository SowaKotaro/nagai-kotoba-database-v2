require "test_helper"

# 詳細検索フォーム(/search)。結果は出さず、送信すると空条件を除いて単語一覧へリダイレクトする。
class SearchesControllerTest < ActionDispatch::IntegrationTest
  test "検索ページは誰でも開け、結果は出さずにフォームだけを描く" do
    get search_path
    assert_response :success
    assert_select "form.search-form"
    assert_select ".entry-list", count: 0
  end

  test "検索を実行すると空条件を除いた条件で単語一覧へリダイレクトする" do
    genre_id = genres(:large_literature).id
    kango_id = word_origins(:kango).id
    {
      { q: "カレー", rhythm_pattern: "", char_type_pattern: "", first_char: [ "カ" ], last_char: [] } =>
        { q: "カレー", first_char: [ "カ" ] },
      { genre_id: [ genre_id.to_s ] } => { genre_id: [ genre_id ] },
      { word_origin_id: [ kango_id.to_s ] } => { word_origin_id: [ kango_id ] },
      { char_type_pattern: "漢漢", char_type_partial: "1", char_type_ignore_case: "1" } =>
        { char_type_pattern: "漢漢", char_type_partial: "1", char_type_ignore_case: "1" },
      { regexp: "^ア.*ン$" } => { regexp: "^ア.*ン$" },
      { dakuten_min: "3", small_kana_min: "", chouon_min: "0" } => { dakuten_min: 3 }
    }.each do |params, expected|
      get search_path, params: { commit: I18n.t("searches.submit") }.merge(params)
      assert_redirected_to words_path(expected)
    end
  end

  test "commit なし(リンクからの遷移)はリダイレクトせずフォームに条件を反映する" do
    get search_path, params: { q: "カレー" }
    assert_response :success
    assert_select "input#q[value=?]", "カレー"
  end

  test "不正・長すぎる正規表現はリダイレクトせず、入力を残して理由を伝える" do
    get search_path, params: { commit: I18n.t("searches.submit"), regexp: "(ア" }
    assert_response :success
    assert_select "input#regexp[value=?]", "(ア"
    assert_select ".flash--alert", text: /#{I18n.t('searches.regexp_error.syntax')}/

    get search_path, params: { commit: I18n.t("searches.submit"), regexp: "ア" * (SearchRegexp::MAX_LENGTH + 1) }
    assert_response :success
    assert_select ".flash--alert", text: /#{I18n.t('searches.regexp_error.too_long')}/
  end

  # --- 文字種(キーボード風の入力。キーを押す挙動は SearchCharTypeTest で見る) ---
  test "文字種はキー・削除キー・コンソール表示で組み、既定は厳密(完全一致・大文字小文字を区別)" do
    get search_path
    %w[あ ア 漢 1 A a @].each do |char|
      assert_select "button.char-type-key[data-char-type-char-param=?]", char, text: char
    end
    assert_select "button.char-type-key[data-char-type-target=lowerKey]:not([hidden])"
    assert_select "button.char-type-key--backspace[data-action=?]", "char-type#remove"
    # 送信値は hidden、組み立て表示はコンソール(display ターゲット)。手入力できる text 欄は無い
    assert_select "input[type=hidden]#char_type_pattern"
    assert_select ".char-type-display [data-char-type-target=display]"
    assert_select "input[type=text]#char_type_pattern", count: 0
    # 切替アイコン(Aa/ab)は点灯(aria-pressed=true)で、緩い側のときだけ "1" を持つ hidden は空
    assert_select "button.char-type-flag__btn[aria-pressed=true]", count: 2
    assert_select "input[type=hidden][name=char_type_partial][value=?]", ""
    assert_select "input[type=hidden][name=char_type_ignore_case][value=?]", ""
  end

  test "緩い側の指定で開くと切替アイコンが消灯し、「a」キーは最初から隠れている" do
    get search_path, params: { char_type_pattern: "漢", char_type_partial: "1", char_type_ignore_case: "1" }
    assert_select "button.char-type-flag__btn[aria-pressed=false]", count: 2
    assert_select "input[type=hidden][name=char_type_partial][value=?]", "1"
    assert_select "input[type=hidden][name=char_type_ignore_case][value=?]", "1"
    # 大文字小文字を区別しないとき「a」は「A」に畳まれるので、JS を待たずにサーバが隠しておく
    assert_select "button.char-type-key[data-char-type-target=lowerKey][hidden]"
  end

  test "語種・母音パターン・正規表現(畳んだ早見表つき)の入力欄がある" do
    get search_path
    word_origins(:kango, :eigo).each do |origin|
      assert_select "input[type=checkbox][name=?][value=?]", "word_origin_id[]", origin.id.to_s
    end
    assert_select "input#vowel_reading"
    # 音の成分は3つとも「◯つ以上」の数値欄で、条件を引き継いで開くと値が入っている
    get search_path, params: { dakuten_min: "4" }
    assert_select "fieldset.sound-count-field input[type=number]", count: 3
    assert_select "input#dakuten_min[value=?]", "4"
    assert_select ".field-hint", text: I18n.t("searches.vowel_pattern_hint")

    # 正規表現の書き方は既定で畳まれたヘルプに入れて目立たせず、入力欄と aria-describedby で結ぶ
    assert_select "input#regexp[aria-describedby=?]", "regexp-help"
    assert_select "details.field-help#regexp-help"
    assert_select "details.field-help[open]", count: 0
    assert_select "summary.field-help__summary", text: /#{I18n.t('searches.regexp_help.summary')}/
    assert_select ".regexp-help__table dt", text: "^ア"
    assert_select ".regexp-help__table dd", text: "アで始まる"
    assert_select ".field-help__note", text: I18n.t("searches.regexp_help.note")
  end

  # --- ジャンルの折り畳み(1,131件のチップをフラグメントキャッシュに載せている) ---
  # テスト環境は既定でキャッシュ無効なので、そのままでは「キャッシュに載せたせいで壊れる」類のバグ
  # (選択状態の混線・マスタ更新時の無効化漏れ)を検出できない。ここだけキャッシュを有効にして描く。

  test "ジャンルの折り畳みは選んだ枝だけ開き、キャッシュしても選択が混線しない" do
    novel = genres(:small_novel)
    other = Genre.create!(name: "混線確認用の小分類", parent: genres(:medium_japanese), level: :small)

    with_fragment_cache do
      get search_path
      assert_select "details.genre-fold", minimum: 1
      assert_select "details.genre-fold[open]", count: 0
      # 大分類チップは「◯◯ 全体」のラベルで出る
      assert_select ".check-chip__face", text: I18n.t("searches.whole_genre", name: genres(:large_literature).name)

      # 小「小説」を選ぶと、その枝(大「文学」・中「日本文学」)が開き、選択数が summary に出る
      get search_path, params: { genre_id: [ novel.id ] }
      assert_select "details.genre-fold[open]", count: 2
      assert_select "details.genre-fold[open] .genre-fold__count", text: "1", count: 2
      assert_genre_checked novel, true
      assert_genre_checked other, false

      # 別の選択で開き直しても、前のリクエストのキャッシュは返らない
      get search_path, params: { genre_id: [ other.id ] }
      assert_genre_checked other, true
      assert_genre_checked novel, false

      # 選択の順序が違っても同じ結果になる
      get search_path, params: { genre_id: [ novel.id, other.id ] }
      fragment = genre_filter_fragment
      get search_path, params: { genre_id: [ other.id, novel.id ] }
      assert_equal fragment, genre_filter_fragment

      # 条件なしへ戻すと、どれも選ばれていない状態に戻る
      get search_path
      assert_genre_checked novel, false
      assert_genre_checked other, false
      assert_select "details.genre-fold[open]", count: 0
    end
  end

  test "ジャンルを改名・追加・削除するとフィルタのキャッシュが作り直される" do
    with_fragment_cache do
      get search_path
      assert_select ".check-chip__face", text: genres(:small_novel).name

      genres(:small_novel).update!(name: "改名した小分類")
      get search_path
      assert_select ".check-chip__face", text: "改名した小分類"

      added = Genre.create!(name: "追加した小分類", parent: genres(:medium_japanese), level: :small)
      get search_path
      assert_select ".check-chip__face", text: "追加した小分類"

      added.destroy!
      get search_path
      assert_select ".check-chip__face", text: "追加した小分類", count: 0
    end
  end

  private

  # フラグメントキャッシュの書き込み先は Rails.cache ではなく、起動時に取り込んだ
  # ActionController::Base.cache_store(テストでは NullStore)。差し替えるのはこちら。
  def with_fragment_cache
    original_perform_caching = ActionController::Base.perform_caching
    original_store = ActionController::Base.cache_store
    ActionController::Base.perform_caching = true
    ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    ActionController::Base.perform_caching = original_perform_caching
    ActionController::Base.cache_store = original_store
  end

  def assert_genre_checked(genre, checked)
    assert_select "input[type=checkbox][name=?][value=?][checked]", "genre_id[]", genre.id.to_s, count: checked ? 1 : 0
  end

  # CSRF トークンなど毎回変わる要素を巻き込まずに比べるため、区画だけを取り出す。
  def genre_filter_fragment
    response.body[/<div class="genre-filter".*?<\/fieldset>/m] ||
      flunk("ジャンルフィルタの区画が描画されていない")
  end
end
