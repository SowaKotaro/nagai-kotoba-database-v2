require "test_helper"

# 収録統計ページ(/stats)。集計値そのものは SiteStatisticsTest、図の組み立て(ツリーマップの畳み方・
# 母音グラフの座標)は StatsHelperTest で押さえ、ここでは各章が描かれ、検索への導線になっていることを見る。
# 1回の描画で全章を集計して重いので、同じデータで確かめられるものは1回の GET にまとめる。
class StatsControllerTest < ActionDispatch::IntegrationTest
  test "統計ページは誰でも見られ、各章の図が描かれる" do
    get stats_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("stats.index.title")
    assert_select "meta[name=robots]", count: 0

    # 数字の壁は4群×5指標の定義リスト
    assert_select ".stats-wall__group", count: 4
    assert_select ".stats-wall__row", count: 20
    # 50音表(先頭文字 / 末尾文字)・行×行・波形バー(文字数 / モーラ数)・推移・スペクトル・頭子音(s / k)
    assert_select ".stats-kana .kana-grid", count: 2
    assert_select "table.sound-matrix", count: 1
    assert_select "svg.wave-chart", count: 2
    assert_select "svg.timeline-chart", minimum: 1
    assert_select "svg.vowel-spectrum", count: 1
    assert_select ".stats-bars__row", minimum: 2
    # 特徴ランキングの実例は該当部分を span で示す
    assert_select ".feature-rank__target", text: "殺人"
    # アノテーション依存の章には集計対象の語義数を明示する
    assert_select ".stats-covered", text: I18n.t("stats.index.annotated_note", count: 1), minimum: 1

    # ジャンルのサンバーストは大→中→小の階層データ(Plotly 形式)を埋め込み、段階展開の受け皿を隠して置く
    assert_select ".genre-analysis[data-controller=genre-sunburst]", count: 1
    assert_select "[data-genre-sunburst-target=mediumBar]", count: 1
    assert_select ".tag-row[data-genre-sunburst-target=smallList]", count: 1
    large = genres(:large_literature)
    medium = genres(:medium_japanese)
    small = genres(:small_novel)
    data = JSON.parse(css_select("script[data-genre-sunburst-target=data]").first.text)
    assert_equal [ "文学", "日本文学", "小説" ], data["labels"]
    assert_equal [ "L#{large.id}", "M#{medium.id}", "S#{small.id}" ], data["ids"]
    assert_equal [ "", "L#{large.id}", "M#{medium.id}" ], data["parents"]
    assert_equal [ 1, 1, 1 ], data["values"]
    assert_equal [ large.id, medium.id, small.id ], data["genre_ids"]

    # 母音の遷移グラフは層ごとに5ノード。色を持つのは押して選んだ線だけで、既定で塗られている線は無い
    layers = SiteStatistics.new.vowel_transitions[:layers].size
    assert_operator layers, :>=, 2
    assert_select "svg.vowel-graph circle.vowel-graph__node", count: layers * 5
    assert_select "svg.vowel-graph line.vowel-graph__edge", minimum: 1
    assert_select "svg.vowel-graph line.is-selected", count: 0
    # 段名(ア段〜オ段)は、横スクロールしない左の列に1度だけ
    assert_select "svg.vowel-graph text.vowel-graph__label", count: 0
    assert_select "svg.vowel-graph__rows text.vowel-graph__label", count: 5

    # ワードクラウド(Issue 78)は集計ファイルの語をすべて並べ、8色とも使う
    entries = MorphemeFrequencies.entries
    assert_select "section.stats-section--word-cloud"
    assert_select ".word-cloud__link", count: entries.size
    assert_select ".word-cloud__text", count: entries.size
    (1..MorphemeCloud::PALETTE_SIZE).each do |palette|
      assert_select ".word-cloud__text--c#{palette}", minimum: 1
    end
  end

  test "棒・セル・チップは検索の絞り込みへの導線になり、index されない面へは nofollow を付ける" do
    get stats_path
    # 50音表ヒートマップ → 先頭文字 / 末尾文字(読みはカタカナへ正規化される)
    assert_select "a.kana-cell--heat[href=?]", words_path(first_char: "サ")
    assert_select "a.kana-cell--heat[href=?]", words_path(last_char: "レ")
    # 行×行ヒートマップ → 頭文字×末尾文字(サ→ン と カ→ラ の2セル)。
    # どれも複数条件で noindex になるため、クロールもさせない
    assert_select "a.sound-matrix__cell", count: 2
    assert_select "a.sound-matrix__cell[rel=nofollow]", count: 2
    # 頭子音の棒 → 先頭文字。1文字だけの群は canonical と揃うスカラ形で出す
    # (`first_char[]=サ` だと canonical(`first_char=サ`)と URL が食い違う)。単一ファセットなので辿らせる
    assert_select "a.stats-bars__bar[href=?]", words_path(first_char: "サ")
    assert_select "a.stats-bars__bar[href=?]", words_path(first_char: "カ")
    assert_select "a.stats-bars__bar[rel=nofollow]", count: 0
    # エンティティ型・特徴チップ(ジャンルは Plotly サンバースト側で遷移する)
    assert_select "a[href=?]", words_path(entity_type_id: entity_types(:book_title).id)
    assert_select "a[href=?]", words_path(linguistic_feature_id: linguistic_features(:rendaku).id)
    # ワードクラウドの各項目は、その部品を含む語のキーワード検索へ。キーワード検索は必ず noindex
    assert_select "a.word-cloud__link[href=?]", words_path(q: MorphemeFrequencies.entries.first.text)
    assert_select "a.word-cloud__link:not([rel=nofollow])", count: 0
  end

  test "読みの長さの30以上はまとめ棒になり、文字数側だけ nofollow の範囲検索へリンクする" do
    word = Word.create!(surface: "とても長い開発語", annotated_at: Time.current, annotation_status: :done)
    word.word_senses.create!(reading: "ナ" * 35)

    get stats_path
    # 35 は単独の棒にならず「30+」のまとめ棒になる。範囲指定(reading_length_min)は noindex の面
    assert_select "a[href=?]", words_path(reading_length: 35), count: 0
    assert_select "a.wave-chart__bar[href=?][rel=nofollow]",
                  words_path(reading_length_min: SiteStatistics::DISTRIBUTION_OVERFLOW_MIN)
    # モーラ側には範囲検索パラメータが無いため、まとめ棒はリンクにしない
    assert_select "g.wave-chart__bar--static", count: 1
    # ちょうどの値の棒(カレー = 3文字)は単一ファセットとして index されるので辿らせる
    assert_select "a.wave-chart__bar[href=?]:not([rel=nofollow])", words_path(reading_length: 3)
  end

  test "公開語が無ければ空表示にする(例外を出さない)" do
    Word.annotated.destroy_all
    get stats_path
    assert_response :success
    assert_select ".empty-note"
    assert_select "svg.wave-chart", count: 0
  end

  test "集計ファイルが無ければワードクラウドの区画ごと出さない" do
    MorphemeFrequencies.path = Rails.root.join("db/does_not_exist.json")

    get stats_path
    assert_response :success
    assert_select "section.stats-section--word-cloud", count: 0
    # 他の章は通常どおり出る
    assert_select ".stats-wall__list"
  ensure
    MorphemeFrequencies.path = nil
  end
end
