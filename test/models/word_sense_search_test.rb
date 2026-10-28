require "test_helper"

class WordSenseSearchTest < ActiveSupport::TestCase
  # フィクスチャ:
  #   murder  … 読み さつじんじけん(7文字/先頭さ/末尾ん) 韻 satsujinjiken
  #             genre 小説, 品詞 名詞, entity 書籍名, 特徴 連濁/重箱読み
  #   curry   … 読み カレー(3文字/先頭カ/末尾レ。末尾は長音「ー」なので直前の レ) 韻 karee, 品詞 名詞, genre/entity/特徴 なし
  def ids(params)
    WordSenseSearch.new(params).results.pluck(:id).sort
  end

  test "公開(注釈済み)の語義だけを返す" do
    assert_equal WordSense.published.pluck(:id).sort, ids({})

    # 未注釈語の語義は検索結果に出ない
    # pending は未注釈語 pending_haruhi にぶら下がる語義。
    assert_not_includes ids({}), word_senses(:pending).id
    assert_equal [], ids(q: "涼宮ハルヒ")

    # 未注釈語の別表記は検索結果に出ない
    word_senses(:pending).word_sense_variants.create!(surface: "ハルヒの憂鬱", reading: "ハルヒノユウウツ")

    assert_equal [], ids(q: "ハルヒの憂鬱")

    # 正規表現は未注釈語には当たらない
    assert_equal [], ids(regexp: "涼宮")
  end

  # --- キーワード(表層形・読みの部分一致) ---
  test "キーワードは表層形・読み・別表記に部分一致し、清濁は区別してひらがなとカタカナは同一視する" do
    assert_equal [ word_senses(:murder).id ], ids(q: "殺人")

    # キーワードは読みの部分一致でも絞れる
    assert_equal [ word_senses(:murder).id ], ids(q: "さつじん")

    # キーワードの LIKE ワイルドカードはエスケープされる
    assert_equal [], ids(q: "%殺人%")

    # キーワードは別表記の表層形でも絞れる
    # curry_variant … カレーライス(語義 curry)の別表記「カリー」(読みも カリー)
    assert_equal [ word_senses(:curry).id ], ids(q: "カリー")

    # キーワードは別表記の読みでも絞れる
    word_senses(:curry).word_sense_variants.create!(surface: "咖喱", reading: "カリイ")

    assert_equal [ word_senses(:curry).id ], ids(q: "カリイ")

    # 別表記は清濁を区別して一致する
    assert_equal [], ids(q: "ガリー")

    # 別表記はひらがなで書いても一致する
    assert_equal [ word_senses(:curry).id ], ids(q: "かりー")

    # キーワードは清音と濁音を区別しつつ、ひらがなとカタカナは同一視する
    # murder の読みはひらがな「さつじんじけん」。カタカナで引いても一致する
    assert_equal [ word_senses(:murder).id ], ids(q: "サツジン")
    # 濁音違い(ザツジン)は別物として一致しない
    assert_equal [], ids(q: "ザツジン")
  end

  # --- 正規表現(表層形・読み) ---
  # フィクスチャの murder は読みがひらがなだが、実データの読みはカタカナで統一されている。
  # 読みへの一致はカタカナの curry で確かめる。
  test "正規表現は表層形・読みに一致し、壊れた式は条件から外す" do
    assert_equal [ word_senses(:curry).id ], ids(regexp: "^カ.*ー$")

    # 正規表現は表層形に一致でも絞れる
    assert_equal [ word_senses(:murder).id ], ids(regexp: "^ABC.*事件$")

    # 正規表現のひらがな入力はカタカナの読みに一致する
    assert_equal [ word_senses(:curry).id ], ids(regexp: "^かれー$")

    # 正規表現は一致しなければ空
    assert_equal [], ids(regexp: "^ゼッタイニナイヨミ$")

    # 正規表現は他の条件と AND で積む
    assert_equal [], ids(regexp: "^カ.*ー$", first_char: [ "さ" ])

    # 不正な正規表現は :syntax を返し、条件から外して検索する
    search = WordSenseSearch.new(regexp: "(ア")
    assert_equal :syntax, search.regexp_error
    # 壊れた式で SQL エラーにせず、他の条件だけで絞る(ここでは条件なし = 公開全件)。
    assert_equal WordSense.published.pluck(:id).sort, search.results.pluck(:id).sort
  end

  test "引き継ぐ条件・条件の有無・インデックス許可ファセットの判定" do
    assert_equal "^ア.*ン$", WordSenseSearch.new(regexp: "^ア.*ン$").to_query_params[:regexp]

    # 正規表現だけでも絞り込み条件ありと判定する
    assert WordSenseSearch.new(regexp: "^ア").conditions?

    # 正規表現はインデックス許可ファセットにならない
    assert_nil WordSenseSearch.new(regexp: "^ア").indexable_facet

    # 末尾文字の単一指定はインデックス許可ファセットになる(先頭文字と対)
    assert_equal [ :last_char, "ン" ], WordSenseSearch.new(last_char: "ン").indexable_facet
    assert_equal [ :first_char, "ア" ], WordSenseSearch.new(first_char: "ア").indexable_facet

    # 末尾文字の複数指定はインデックス許可ファセットにならない
    assert_nil WordSenseSearch.new(last_char: [ "ン", "ー" ]).indexable_facet

    # 音の成分は引き継ぎ用のクエリに含まれ、インデックス許可ファセットにはならない
    search = WordSenseSearch.new(dakuten_min: "3", chouon_min: "1")
    assert_equal({ dakuten_min: 3, chouon_min: 1 }, search.to_query_params)
    assert_nil search.indexable_facet

    # 母音の遷移は引き継ぐ条件に入り、単独でもインデックスは許可しない
    search = WordSenseSearch.new(vowel_transition: "1-ae")
    assert_equal "1-ae", search.to_query_params[:vowel_transition]
    assert_nil search.indexable_facet

    # OR は条件が2つ以上のときだけ引き継ぎ用のクエリに含め、インデックス許可ファセットにはしない
    # 条件が1つなら AND と同じ結果なので、別の URL を作らない
    single = WordSenseSearch.new(first_char: "カ", match: "any")
    assert_equal({ first_char: [ "カ" ] }, single.to_query_params)
    assert_equal [ "first_char", "カ" ], single.indexable_facet.map(&:to_s)

    search = WordSenseSearch.new(first_char: "カ", last_char: "ん", match: "any")
    assert_equal "any", search.to_query_params[:match]
    assert_nil search.indexable_facet
    # 既知の値("any")以外は AND のまま
    assert_nil WordSenseSearch.new(first_char: "カ", last_char: "ん", match: "or").to_query_params[:match]
  end

  test "読みの文字数・モーラ数・先頭/末尾文字・韻で絞れ、先頭文字は清濁を区別する" do
    result = ids(reading_length_min: "5")
    assert_includes result, word_senses(:murder).id
    assert_not_includes result, word_senses(:curry).id

    # 読みの文字数の上限で絞れる
    result = ids(reading_length_max: "3")
    assert_includes result, word_senses(:curry).id
    assert_not_includes result, word_senses(:murder).id

    # 先頭文字で絞れる
    assert_equal [ word_senses(:murder).id ], ids(first_char: "さ")

    # 末尾文字で絞れる
    assert_equal [ word_senses(:curry).id ], ids(last_char: "レ")

    # 韻の部分一致で絞れる
    assert_equal [ word_senses(:murder).id ], ids(rhythm_pattern: "tsuji")

    # 読みの文字数(完全一致)で絞れる
    assert_equal [ word_senses(:curry).id ], ids(reading_length: "3")

    # モーラ数で絞れる
    assert_equal [ word_senses(:curry).id ], ids(mora_count: "3")

    # 0 や不正な文字数は無視する
    assert_equal WordSense.published.pluck(:id).sort, ids(reading_length_min: "0", reading_length_max: "abc")

    # 先頭文字は清音と濁音・半濁音を区別する
    sense = create_published_word(surface: "バナナジュース", reading: "バナナジュース").word_senses.first

    assert_includes ids(first_char: "バ"), sense.id
    assert_not_includes ids(first_char: "ハ"), sense.id
    assert_not_includes ids(first_char: "パ"), sense.id
  end

  # --- 文字種(words.char_type_pattern)。abc_murder は "AAA漢漢漢漢" ---
  test "文字種は既定で完全一致・大小を区別し、トグルで部分一致・大小の同一視に切り替わる" do
    pattern = words(:abc_murder).char_type_pattern
    assert_equal [ word_senses(:murder).id ], ids(char_type_pattern: pattern)

    # 文字種は既定(完全一致)で部分文字列では絞れない
    assert_equal [], ids(char_type_pattern: "漢漢漢漢")

    # 部分一致トグルを入れると部分文字列でも絞れる
    assert_equal [ word_senses(:murder).id ], ids(char_type_pattern: "漢漢漢漢", char_type_partial: "1")

    # 文字種は既定(大文字小文字を区別)で小文字パターンは一致しない
    assert_equal [], ids(char_type_pattern: "aaa漢漢漢漢")

    # 大小を区別しないトグルを入れると小文字パターンでも一致する
    assert_equal [ word_senses(:murder).id ],
                 ids(char_type_pattern: "aaa漢漢漢漢", char_type_ignore_case: "1")

    # 大小を区別しない文字種の検索では、あ と ア も同一視される
    # words.char_type_pattern は utf8mb4_0900_ai_ci なので、大小を区別しない検索では
    # 「あ」(ひらがな)と「ア」(カタカナ)の記号も同じとみなされる。区別する検索は utf8mb4_bin で比べる。
    word = Word.new(surface: "ひらがなだけのことば")
    word.word_senses.build(reading: "ヒラガナダケノコトバ")
    word.mark_annotated
    word.save!
    assert_equal "ああああああああああ", word.char_type_pattern

    katakana_pattern = "アアアアアアアアアア"
    assert_includes ids(char_type_pattern: katakana_pattern, char_type_ignore_case: "1"), word.word_senses.first.id
    assert_not_includes ids(char_type_pattern: katakana_pattern), word.word_senses.first.id

    # 大小を区別しないとき文字種パターンの小文字は大文字に畳まれる
    search = WordSenseSearch.new(char_type_pattern: "Aa1あ", char_type_ignore_case: "1")
    assert_equal "AA1あ", search.char_type_pattern
    assert_equal "AA1あ", search.to_query_params[:char_type_pattern]

    # 大小を区別するとき文字種パターンの小文字はそのまま残る
    search = WordSenseSearch.new(char_type_pattern: "Aa1あ")
    assert_equal "Aa1あ", search.char_type_pattern
  end

  test "品詞・エンティティ・特徴・ジャンル・語種で絞れ、ジャンルは下位を優先する" do
    result = ids(part_of_speech_id: parts_of_speech(:noun).id)
    assert_includes result, word_senses(:murder).id
    assert_includes result, word_senses(:curry).id

    # エンティティタイプで絞れる
    assert_equal [ word_senses(:murder).id ], ids(entity_type_id: entity_types(:book_title).id)

    # 言語学的特徴で絞れる
    assert_equal [ word_senses(:murder).id ], ids(linguistic_feature_id: linguistic_features(:rendaku).id)

    # ジャンルは大分類を選ぶと配下の小分類で絞れる
    # 文学(大) を選ぶと 小説(小) を持つ murder が該当する。
    assert_equal [ word_senses(:murder).id ], ids(genre_id: genres(:large_literature).id)

    # ジャンルは小分類を直接指定しても絞れる
    assert_equal [ word_senses(:murder).id ], ids(genre_id: genres(:small_novel).id)

    # ジャンルは配列(複数選択)でも絞れる
    assert_equal [ word_senses(:murder).id ], ids(genre_id: [ genres(:small_novel).id.to_s ])

    # ジャンルは上位と下位を同時に選ぶと下位を優先する
    search = WordSenseSearch.new(genre_id: [ genres(:large_literature).id.to_s,
                                             genres(:medium_japanese).id.to_s ])
    assert_equal [ genres(:medium_japanese) ], search.effective_genres

    # ジャンルの実効節点は中抜きの祖先(大と小のみ選択)でも上位を除く
    search = WordSenseSearch.new(genre_id: [ genres(:large_literature).id.to_s,
                                             genres(:small_novel).id.to_s ])
    assert_equal [ genres(:small_novel) ], search.effective_genres

    # 語種で絞れる
    assert_equal [ word_senses(:murder).id ], ids(word_origin_id: word_origins(:kango).id)

    # 語種は複数指定(OR)でも絞れる
    both = ids(word_origin_id: [ word_origins(:kango).id, word_origins(:eigo).id ])
    assert_equal [ word_senses(:curry).id, word_senses(:murder).id ].sort, both

    # 品詞の複数指定(OR)で絞れる
    # murder / curry はいずれも名詞。名詞1つでも配列でも両方返る。
    assert_equal [ word_senses(:curry).id, word_senses(:murder).id ].sort,
                 ids(part_of_speech_id: [ parts_of_speech(:noun).id ])
  end

  test "同じ項目の中は OR、区画どうしは既定で AND・match=any で OR" do
    both = ids(part_of_speech_id: parts_of_speech(:noun).id, first_char: "カ")
    assert_equal [ word_senses(:curry).id ], both

    # match=any なら区画どうしを OR で組む(区画ごとに join が違う条件どうしでも結べる)
    # キーワードは words と別表記を、言語学的特徴は word_sense_features を引く。AND では両方を満たす語義が無い
    params = { q: "カレー", linguistic_feature_id: linguistic_features(:rendaku).id }
    assert_equal [], ids(params)
    assert_equal [ word_senses(:curry).id, word_senses(:murder).id ].sort, ids(params.merge(match: "any"))

    # OR でも区画の中の組み合わせは変わらない(文字数の下限と上限は AND)
    # curry は3文字、murder は7文字。5〜6文字はどちらも満たさないので、先頭文字の分だけが返る
    assert_equal [ word_senses(:curry).id ], ids(reading_length_min: 5, reading_length_max: 6, first_char: "カ", match: "any")

    # 先頭文字は複数指定(OR)で絞れる
    both = ids(first_char: [ word_senses(:murder).first_char, word_senses(:curry).first_char ])
    assert_equal [ word_senses(:curry).id, word_senses(:murder).id ].sort, both

    # 単一値(ファセットリンク)でも配列でも同じ結果になる
    assert_equal ids(first_char: word_senses(:curry).first_char),
                 ids(first_char: [ word_senses(:curry).first_char ])
  end

  # --- 音の成分の個数(「◯つ以上」。words の max_*_count に当てる) ---
  test "音の成分の個数の下限で絞れ、不正な値は無視する" do
    # さつじんじけん の濁点は「じ」2つ、カレー は 0
    assert_equal [ word_senses(:murder).id ], ids(dakuten_min: "2")
    assert_equal [], ids(dakuten_min: "3")

    # 長音符・小書きのかなの数の下限で絞れる
    assert_equal [ word_senses(:curry).id ], ids(chouon_min: "1")
    assert_equal [], ids(small_kana_min: "1")

    # 音の成分は 0・負数・数字でない値を無視する
    assert_equal WordSense.published.pluck(:id).sort, ids(dakuten_min: "0", small_kana_min: "-1", chouon_min: "abc")
  end

  # --- 母音パターン検索(読みのカナ入力 → 母音のみで押韻検索) ---
  test "母音パターン(押韻)と母音の遷移(拍位置で固定)で絞れ、形と範囲が外れた遷移は捨てる" do
    # カレー → karee → 母音 aee。curry の vowel_pattern と一致する。
    result = ids(vowel_reading: "カレー")
    assert_includes result, word_senses(:curry).id
    assert_not_includes result, word_senses(:murder).id

    # 母音パターン検索は部分一致(押韻)で絞れる
    # 「ケー」→ kee → 母音 ee。curry(aee)は末尾で韻を踏むので該当する。
    assert_includes ids(vowel_reading: "ケー"), word_senses(:curry).id

    # 母音の遷移は指定した拍位置の2拍で絞れる
    # curry の母音は aee。1拍目 a → 2拍目 e。
    assert_equal [ word_senses(:curry).id ], ids(vowel_transition: "1-ae")
    assert_equal [ word_senses(:curry).id ], ids(vowel_transition: "2-ee")
    # 位置が違えば当たらない(位置を問わない押韻検索とは別物)
    assert_equal [], ids(vowel_transition: "3-ae")

    # 母音の遷移は3拍以上つなげた並びでも絞れる
    # curry の母音は aee。1拍目から a → e → e。
    assert_equal [ word_senses(:curry).id ], ids(vowel_transition: "1-aee")
    assert_equal [], ids(vowel_transition: "1-aea")

    # 母音の遷移は読みがそこまで続かない語義を外す
    # curry は3拍(aee)しかないので、3拍目から先の組には該当しない。
    assert_not_includes ids(vowel_transition: "3-ea"), word_senses(:curry).id

    # 母音の遷移は形が違えば条件ごと無視する
    all = ids({})
    assert_equal all, ids(vowel_transition: "1-xy")   # 母音でない
    assert_equal all, ids(vowel_transition: "ae")     # 位置が無い
    assert_equal all, ids(vowel_transition: "0-ae")   # 拍位置は1から
    assert_equal all, ids(vowel_transition: "1-a")    # 1拍では遷移にならない
    assert_equal all, ids(vowel_transition: "1-#{'a' * 16}") # 並びは15拍まで
    assert_equal all, ids(vowel_transition: "99-ae")  # 上限より後ろ
    assert_not WordSenseSearch.new(vowel_transition: "1-xy").conditions?

    # 母音の遷移の境界: 並びは15拍まで・拍位置は30まで受ける
    # 上限は 2 つの定数が別々に持つ(並びの長さは VOWEL_TRANSITION_FORMAT の 15、拍位置は
    # VOWEL_TRANSITION_MAX_POSITION の 30)。境界の内側は条件に残り、外側は条件ごと捨てる。
    fifteen = "1-#{'a' * 15}"
    assert_equal fifteen, WordSenseSearch.new(vowel_transition: fifteen).vowel_transition
    assert_equal "", WordSenseSearch.new(vowel_transition: "1-#{'a' * 16}").vowel_transition

    assert_equal "30-ae", WordSenseSearch.new(vowel_transition: "30-ae").vowel_transition
    assert_equal "", WordSenseSearch.new(vowel_transition: "31-ae").vowel_transition
    assert_not WordSenseSearch.new(vowel_transition: "31-ae").conditions?
  end

  test "受け付けるパラメータ(PERMITTED_PARAMS)は、単語一覧へ引き継ぐ条件(to_query_params)のキーをすべて含む" do
    all = {
      q: "a", regexp: "a", reading_length_min: "10", reading_length_max: "20", reading_length: "12", mora_count: "12",
      dakuten_min: "1", small_kana_min: "1", chouon_min: "1", first_char: %w[ア], last_char: %w[ン], genre_id: %w[1],
      part_of_speech_id: %w[1], entity_type_id: %w[1], linguistic_feature_id: %w[1], word_origin_id: %w[1],
      rhythm_pattern: "a", vowel_reading: "ア", vowel_transition: "1-ae",
      char_type_pattern: "漢", char_type_partial: "1", char_type_ignore_case: "1", match: "any"
    }
    permitted = ActionController::Parameters.new(all).permit(*WordSenseSearch::PERMITTED_PARAMS)

    assert_equal all.keys.sort, WordSenseSearch.new(permitted).to_query_params.keys.sort
    # 複数選択の条件は、ファセットのリンクから単一値で来ても受け付ける
    assert_equal({ "first_char" => "ア" }, ActionController::Parameters.new(first_char: "ア").permit(*WordSenseSearch::PERMITTED_PARAMS).to_h)
  end
end
