require "test_helper"

# 詳細検索フォーム(/search)。結果は出さず、送信すると空条件を除いて単語一覧へリダイレクトする。
class SearchesControllerTest < ActionDispatch::IntegrationTest
  test "検索ページは誰でも開け、結果は出さずにフォームだけを描く(キーワード以外の区画は畳み、テキスト欄の確定キーは「検索」)" do
    get search_path
    assert_response :success
    assert_select "form.search-form"
    assert_select ".entry-list", count: 0
    # 区画どうしの組み合わせのスイッチは見出しの行にあり、form 属性でフォームに結ぶ。既定は AND(オフ)
    assert_select ".search-head input#match[type=checkbox][role=switch][form=search-form][value=?]", WordSenseSearch::MATCH_ANY
    assert_select "input#match[checked]", count: 0
    assert_select "form#search-form"
    # キーワードだけを常に出し、ほかの条件は区画ごとに見出しだけへ畳んで描く
    assert_select "form.search-form > .field input#q"
    assert_select "details.search-section", minimum: 1
    assert_select "details.search-section[open]", count: 0
    # テキスト欄はどれも Enter で送信できるので、モバイルのキーボードの確定キーも揃えて「検索」にする
    assert_select "form.search-form input[type=text]", minimum: 1
    assert_select "form.search-form input[type=text]:not([enterkeyhint=search])", count: 0
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

  test "単語一覧の「条件を変える」から来た条件を、単一値もフォームに欄の無い条件も落とさずに引き継ぐ" do
    noun = parts_of_speech(:noun)
    carried = { reading_length: "12", mora_count: "11", vowel_transition: "1-ae" }

    # ファセットのリンクは単一値で来る(first_char=ア)。フォームのチェックに反映する
    get search_path, params: { first_char: "ア", part_of_speech_id: noun.id.to_s, **carried }
    assert_response :success
    assert_select "input[name='first_char[]'][value=?][checked]", "ア"
    assert_select "input[name='part_of_speech_id[]'][value=?][checked]", noun.id.to_s
    # 条件が入った区画だけを開き、見出しに選択数を出す(ほかの区画は畳んだまま)
    assert_equal [ "#{I18n.t('searches.first_char')} 1", "#{WordSense.human_attribute_name(:part_of_speech)} 1" ],
                 css_select("details.search-section[open] > summary").map { |summary| summary.text.squish }
    # フォームに欄の無い条件(文字数ちょうど・モーラ数・母音のつながり)は、hidden で持ち回す
    carried.each { |key, value| assert_select "input[type=hidden][name=?][value=?]", key.to_s, value }

    # 検索を実行しても、それらの条件は単語一覧へ引き継がれる
    get search_path, params: { commit: "1", first_char: "ア", **carried }
    assert_redirected_to words_path(first_char: [ "ア" ], reading_length: 12, mora_count: 11, vowel_transition: "1-ae")
  end

  test "OR(match=any)は、条件が2つ以上あるときだけスイッチに引き継ぎ、単語一覧へも渡す" do
    get search_path, params: { match: WordSenseSearch::MATCH_ANY, first_char: "ア", last_char: "ン" }
    assert_select "input#match[checked]"
    get search_path, params: { commit: "1", match: WordSenseSearch::MATCH_ANY, first_char: "ア", last_char: "ン" }
    assert_redirected_to words_path(first_char: [ "ア" ], last_char: [ "ン" ], match: WordSenseSearch::MATCH_ANY)

    # 条件が1つなら AND と同じ結果なので、OR は落とす
    get search_path, params: { match: WordSenseSearch::MATCH_ANY, first_char: "ア" }
    assert_select "input#match[checked]", count: 0
  end

  test "50音表は /browse と同じく公開語義数の濃淡で塗り、0 件のセルは淡くする" do
    # 公開語は カレーライス(読み カレー)と 殺人事件(読み さつじんじけん)
    get search_path
    [ [ "first_char", "カ" ], [ "last_char", "レ" ] ].each do |name, kana|
      assert_select "label.kana-cell--heat[style*='--fill: 1.0']:has(input[name='#{name}[]'][value=?])", kana
      assert_select "label.kana-cell--muted:has(input[name='#{name}[]'][value=?])", "ヲ"
    end
    assert_select "label.kana-cell[title=?]", I18n.t("searches.kana_count_label", char: "カ", count: 1)
  end

  test "読みの文字数のスライダーに目盛りごとの公開語義数を棒で敷き、上端の棒には上端より長い語義もまとめる" do
    lowest, highest = WordSense::MIN_READING_LENGTH, SearchesHelper::READING_LENGTH_SLIDER_MAX
    create_published_word(surface: "十二文字の語その一", reading: "ア" * 12)
    create_published_word(surface: "十二文字の語その二", reading: "イ" * 12)
    create_published_word(surface: "上端より長い語その一", reading: "ウ" * (highest + 1))
    create_published_word(surface: "上端より長い語その二", reading: "エ" * (highest + 5))

    get search_path, params: { reading_length_min: 12, reading_length_max: 14 }
    assert_select ".length-slider__histogram[style=?]", "--steps: #{highest - lowest}"
    assert_select ".length-slider__bar", count: highest - lowest + 1
    # 最多の棒(12文字の 2 件・上端の 2 件)を高さ 1 とする
    assert_select ".length-slider__bar[data-value='12'][style*='--h: 1.0']"
    assert_select ".length-slider__bar[data-value='#{highest}'][style*='--h: 1.0']"
    assert_select ".length-slider__bar[data-value='13'][style*='--h: 0.0']"
    # 選んだ範囲(12〜14文字)の棒だけを濃くする
    assert_equal %w[12 13 14], css_select(".length-slider__bar.is-selected").map { |bar| bar["data-value"] }
  end

  test "不正・長すぎる正規表現はリダイレクトせず、入力を残して理由を伝える" do
    get search_path, params: { commit: I18n.t("searches.submit"), regexp: "(ア" }
    assert_response :success
    assert_select "input#regexp[value=?]", "(ア"
    # 直すべき入力が畳まれて見えなくならないよう、正規表現の区画は開いて描く
    assert_select "details.search-section[open] input#regexp"
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

  test "語種・言語学的特徴(用語解説の順・畳んだ用語解説つき)・母音パターン・正規表現(畳んだ早見表つき)の入力欄がある" do
    %w[ゴママヨ ハ行転呼].each { |name| LinguisticFeature.create!(name:) }
    get search_path
    word_origins(:kango, :eigo).each do |origin|
      assert_select "input[type=checkbox][name=?][value=?]", "word_origin_id[]", origin.id.to_s
    end
    # 言語学的特徴のチップは id 順ではなく、管理画面と同じく用語解説の順(LinguisticFeature.in_glossary_order)
    assert_equal %w[連濁 ハ行転呼 重箱読み ゴママヨ],
                 css_select("input[name='linguistic_feature_id[]'] + .check-chip__face").map(&:text)
    assert_select "input#vowel_reading"
    # 音の成分は3つとも「◯つ以上」の数値欄で、条件を引き継いで開くと値が入っている
    get search_path, params: { dakuten_min: "4" }
    assert_select "fieldset.sound-count-field input[type=number]", count: 3
    assert_select "input#dakuten_min[value=?]", "4"
    assert_select ".field-hint", text: I18n.t("searches.vowel_pattern_hint")

    # 区画の見出しが欄の名前を兼ねるが、畳める入力欄にも名前(label)は残す
    %w[regexp vowel_reading rhythm_pattern].each { |id| assert_select "label[for=?]", id }
    # 正規表現の書き方は既定で畳まれたヘルプに入れて目立たせず、入力欄と aria-describedby で結ぶ
    assert_select "input#regexp[aria-describedby=?]", "regexp-help"
    assert_select "details.field-help#regexp-help"
    assert_select "details.field-help[open]", count: 0
    assert_select "summary.field-help__summary", text: /#{I18n.t('searches.regexp_help.summary')}/
    assert_select ".regexp-help__table dt", text: "^ア"
    assert_select ".regexp-help__table dd", text: "アで始まる"
    assert_select ".field-help__note", text: I18n.t("searches.regexp_help.note")
    # 言語学的特徴の区画にも、管理画面と同じ用語解説を畳んで添える(上の [open] count: 0 で既定は閉じている)
    assert_select "details.search-section fieldset:has(input[name='linguistic_feature_id[]']) + details.field-help" do
      assert_select "summary.field-help__summary", text: /#{I18n.t('searches.feature_glossary_summary')}/
      assert_select ".feature-glossary__item", count: LinguisticFeatureGlossary.all.size
      assert_select ".feature-glossary__item dt", text: "音韻添加"
      assert_select ".feature-glossary__item dd", text: /まんなか/
    end
  end

  # --- ジャンルの折り畳み(1,131件のチップをフラグメントキャッシュに載せている) ---
  # テスト環境は既定でキャッシュ無効なので、そのままでは「キャッシュに載せたせいで壊れる」類のバグ
  # (選択状態の混線・マスタ更新時の無効化漏れ)を検出できない。ここだけキャッシュを有効にして描く。

  test "ジャンルの折り畳みは選んだ枝だけ開き、キャッシュしても選択が混線しない" do
    novel = genres(:small_novel)
    other = Genre.create!(name: "混線確認用の小分類", parent: genres(:medium_japanese), level: :small)
    # 公開語義の無い分類は出さないので、公開語を 1 つ付けておく
    create_published_word(surface: "混線確認用の語", reading: "コンセンカクニンヨウノゴ", genre: other)

    with_fragment_cache do
      get search_path
      assert_select "details.genre-fold", minimum: 1
      assert_select "details.genre-fold[open]", count: 0
      # 大分類チップは「◯◯ 全体」のラベルで出る
      assert_select ".check-chip__face span", text: I18n.t("searches.whole_genre", name: genres(:large_literature).name)

      # 小「小説」を選ぶと、その大分類「文学」が開き、選択数が summary に出る
      get search_path, params: { genre_id: [ novel.id ] }
      assert_select "details.genre-fold[open]", count: 1
      assert_select "details.genre-fold[open] .genre-fold__count", text: "1", count: 1
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

  test "ジャンルを改名・追加・削除したり公開語義数が変わったりすると、フィルタのキャッシュが作り直される" do
    with_fragment_cache do
      get search_path
      assert_select ".check-chip__face span", text: genres(:small_novel).name

      genres(:small_novel).update!(name: "改名した小分類")
      get search_path
      assert_select ".check-chip__face span", text: "改名した小分類"

      # 公開語義の無い分類は出さず、公開語が付いたら出す(マスタは変わらず、公開語義数だけが変わる)
      added = Genre.create!(name: "追加した小分類", parent: genres(:medium_japanese), level: :small)
      get search_path
      assert_select ".check-chip__face span", text: "追加した小分類", count: 0
      word = create_published_word(surface: "追加した分類の語", reading: "ツイカシタブンルイノゴ", genre: added)
      get search_path
      assert_select ".check-chip__face span", text: "追加した小分類"

      word.destroy!
      added.destroy!
      get search_path
      assert_select ".check-chip__face span", text: "追加した小分類", count: 0
    end
  end

  private

  def assert_genre_checked(genre, checked)
    assert_select "input[type=checkbox][name=?][value=?][checked]", "genre_id[]", genre.id.to_s, count: checked ? 1 : 0
  end

  # CSRF トークンなど毎回変わる要素を巻き込まずに比べるため、区画だけを取り出す。
  def genre_filter_fragment
    response.body[/<div class="genre-filter".*?<\/fieldset>/m] ||
      flunk("ジャンルフィルタの区画が描画されていない")
  end
end
