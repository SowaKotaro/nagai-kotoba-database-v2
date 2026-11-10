require "test_helper"

class SearchHighlightTest < ActiveSupport::TestCase
  test "キーワードは表層形・読みの当たった箇所を囲み、別表記だけが当たった語は別表記を返す" do
    curry = words(:curry)
    highlight = highlight_for({ q: "かれ" }, curry)
    assert_equal [ [ 0...2, false ] ], spans(highlight.surface(curry))
    assert_equal [ [ 0...2, false ] ], spans(highlight.reading(curry, "カレー"))
    assert_equal [], highlight.matched_variants(curry)

    # 別表記(カリー)だけが当たった語は、表層形・読みを囲まずに、当たった別表記を返す
    highlight = highlight_for({ q: "カリー" }, curry)
    assert_equal [], highlight.surface(curry)
    assert_equal [ word_sense_variants(:curry_variant) ], highlight.matched_variants(curry)

    # キーワードが無ければ何も囲まない
    highlight = highlight_for({}, curry)
    assert_equal [], highlight.surface(curry)
    assert_equal [], highlight.matched_variants(curry)
  end

  test "正規表現は MySQL の照合で当たった箇所をすべて囲む(大文字小文字は畳み、空の当たりは囲まない)" do
    word = create_published_word(surface: "ABCabc殺人事件", reading: "エービーシーエービーシーサツジンジケン")
    murder = words(:abc_murder)

    highlight = highlight_for({ regexp: "b." }, word, murder)
    assert_equal [ [ 1...3, false ], [ 4...6, false ] ], spans(highlight.surface(word))
    assert_equal [ [ 1...3, false ] ], spans(highlight.surface(murder))

    # 読みにはカタカナへ畳んだパターンを当てる(SearchRegexp#for_reading)
    highlight = highlight_for({ regexp: "じけん$" }, word)
    assert_equal [ [ 16...19, false ] ], spans(highlight.reading(word, "エービーシーエービーシーサツジンジケン"))

    # 空の当たりしか無いパターンと、不正なパターンは囲まない
    assert_equal [], highlight_for({ regexp: "x*" }, word).surface(word)
    assert_equal [], highlight_for({ regexp: "(" }, word).surface(word)
  end

  test "言語学的特徴は絞り込んだ特徴の該当部分を囲み、重なった字だけを濃くする" do
    murder = words(:abc_murder)
    rendaku = linguistic_features(:rendaku)
    jubako = linguistic_features(:jubako)

    highlight = highlight_for({ linguistic_feature_id: [ rendaku.id.to_s ] }, murder)
    assert_equal [ [ 3...5, false ] ], spans(highlight.surface(murder))
    assert_equal [ [ 0...4, false ] ], spans(highlight.reading(murder, "さつじんじけん"))

    # 接するだけなら濃くせず、1 つに続けて囲む
    highlight = highlight_for({ linguistic_feature_id: [ rendaku.id.to_s, jubako.id.to_s ] }, murder)
    assert_equal [ [ 3...7, false ] ], spans(highlight.surface(murder))
    assert_equal [ [ 0...7, false ] ], spans(highlight.reading(murder, "さつじんじけん"))

    # 該当部分が重なった字は濃い(該当部分ごとに 1 枚の層。同じ特徴の 2 か所でも重なれば濃い)
    word = create_published_word(surface: "ゴゴゴゴブリン", reading: "ゴゴゴゴブリン")
    sense = word.word_senses.first
    sense.word_sense_features.create!(linguistic_feature: rendaku, target: "ゴゴゴ", target_reading: "ゴゴゴ", target_start: 0)
    sense.word_sense_features.create!(linguistic_feature: jubako, target: "ゴゴ", target_reading: "ゴゴ", target_start: 2)
    highlight = highlight_for({ linguistic_feature_id: [ rendaku.id.to_s, jubako.id.to_s ] }, word)
    expected = [ [ 0...2, false ], [ 2...3, true ], [ 3...4, false ] ]
    assert_equal expected, spans(highlight.surface(word))
    assert_equal expected, spans(highlight.reading(word, "ゴゴゴゴブリン"))

    # キーワードと特徴のように、条件が違っても重なれば濃い
    highlight = highlight_for({ q: "リン", linguistic_feature_id: [ rendaku.id.to_s ] }, word)
    assert_equal [ [ 0...3, false ], [ 5...7, false ] ], spans(highlight.surface(word))
    highlight = highlight_for({ q: "ゴゴ", linguistic_feature_id: [ rendaku.id.to_s ] }, word)
    assert_equal [ [ 0...3, true ], [ 3...4, false ] ], spans(highlight.surface(word))

    # 同じ該当部分が繰り返し現れる語は、表層形で何番目の出現かに合わせて、読みでも同じ番目を囲む
    word = create_published_word(surface: "びしょびしょ雨びしょびしょ", reading: "ビショビショアメビショビショ")
    word.word_senses.first.word_sense_features.create!(linguistic_feature: rendaku, target: "びしょびしょ",
                                                       target_reading: "ビショビショ", target_start: 7)
    highlight = highlight_for({ linguistic_feature_id: rendaku.id.to_s }, word)
    assert_equal [ [ 7...13, false ] ], spans(highlight.surface(word))
    assert_equal [ [ 8...14, false ] ], spans(highlight.reading(word, "ビショビショアメビショビショ"))
  end

  test "ローマ字・母音・音の成分は、読みのうち当たった字を囲み、表層形は囲まない" do
    reading = "ガッコウスイセンガタセンバツ"
    word = create_published_word(surface: "学校推薦型選抜", reading: reading)

    # ローマ字は拍の途中で当たっても字ごと囲む(kkou → 促音から「ウ」まで、ng → 「ン」と「ガ」)。大文字でも当たる
    highlight = highlight_for({ rhythm_pattern: "KKOU" }, word)
    assert_equal [], highlight.surface(word)
    assert_equal [ [ 1...4, false ] ], spans(highlight.reading(word, reading))
    assert_equal [ [ 7...9, false ] ], spans(highlight_for({ rhythm_pattern: "ng" }, word).reading(word, reading))

    # 母音は入力したカナの母音の並び(センバツ → eau)で当たった字を囲む。母音を持たない「ン」も間にあれば囲む
    highlight = highlight_for({ vowel_reading: "センバツ" }, word)
    assert_equal [], highlight.surface(word)
    assert_equal [ [ 10...14, false ] ], spans(highlight.reading(word, reading))

    # 母音の遷移は拍位置で固定した並び(1-ao = 1 つ目と 2 つ目の母音が a・o → 「ガ」から「コ」まで)
    assert_equal [ [ 0...3, false ] ], spans(highlight_for({ vowel_transition: "1-ao" }, word).reading(word, reading))
    assert_equal [], highlight_for({ vowel_transition: "1-ii" }, word).reading(word, reading)

    # 音の成分は数えた字を成分ごとに囲む(続く字は 1 つにまとめる)
    highlight = highlight_for({ dakuten_min: "1", small_kana_min: "1" }, word)
    assert_equal [ [ 0...2, false ], [ 8...9, false ], [ 12...13, false ] ], spans(highlight.reading(word, reading))

    # ローマ字と音の成分の両方に当たった字は濃い
    highlight = highlight_for({ rhythm_pattern: "gakkou", dakuten_min: "1" }, word)
    assert_equal [ [ 0...1, true ], [ 1...4, false ], [ 8...9, false ], [ 12...13, false ] ],
                 spans(highlight.reading(word, reading))

    # 畳むと字数が変わる読み(半角カナ)は、ローマ字・母音では囲まない
    assert_equal [], highlight_for({ rhythm_pattern: "ga" }, word).reading(word, "ｶﾞｯｺｳ")
  end

  private

  def spans(list) = list.map { |span| [ span.range, span.deep ] }

  # 一覧と同じく、条件はコントローラと同じ許可の集合を通して渡す
  def highlight_for(params, *words)
    search = WordSenseSearch.new(ActionController::Parameters.new(params).permit(*WordSenseSearch::PERMITTED_PARAMS))
    SearchHighlight.new(search, words)
  end
end
