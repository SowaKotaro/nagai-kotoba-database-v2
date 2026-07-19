require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  test "統計ページは未認証で閲覧できる" do
    get stats_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("stats.index.title")
    assert_select "meta[name=robots]", count: 0
  end

  test "数字の壁は4群×5指標の定義リストで組む" do
    get stats_path
    assert_select ".stats-wall__group", count: 4
    assert_select ".stats-wall__row", count: 20
  end

  test "各チャートが描画される(50音表・行×行・波形バー・推移・サンバースト・スペクトル)" do
    get stats_path
    assert_select ".stats-kana .kana-grid", count: 2 # 先頭文字 / 末尾文字の50音表
    assert_select "table.sound-matrix", count: 1
    assert_select "svg.wave-chart", count: 2         # 文字数 / モーラ数の2枚を事前描画
    assert_select "svg.timeline-chart", minimum: 1
    assert_select ".genre-analysis[data-controller=genre-sunburst]", count: 1
    # 段階展開の受け皿(中分類の棒・小分類のタグ一覧)が最初は隠れて置かれている
    assert_select "[data-genre-sunburst-target=mediumBar]", count: 1
    assert_select ".tag-row[data-genre-sunburst-target=smallList]", count: 1
    assert_select "svg.vowel-spectrum", count: 1
    assert_select ".stats-bars__row", minimum: 2     # 頭子音(s / k)
  end

  test "棒・セル・扇は検索の絞り込みへの導線になっている" do
    get stats_path
    # 50音表ヒートマップ → 先頭文字 / 末尾文字(読みはカタカナへ正規化される)
    assert_select "a.kana-cell--heat[href=?]", words_path(first_char: "サ")
    assert_select "a.kana-cell--heat[href=?]", words_path(last_char: "レ")
    # 波形バー → 読みの文字数(カレー = 3文字)
    assert_select "a[href=?]", words_path(reading_length: 3)
    # 行×行ヒートマップ → 頭文字×末尾文字(サ→ン と カ→ラ の2セル)
    assert_select "a.sound-matrix__cell", count: 2
    # エンティティ型・特徴チップ(ジャンルは Plotly サンバースト側で遷移する)
    assert_select "a[href=?]", words_path(entity_type_id: entity_types(:book_title).id)
    assert_select "a[href=?]", words_path(linguistic_feature_id: linguistic_features(:rendaku).id)
  end

  test "ジャンルのサンバーストは大→中→小の階層データ(Plotly 形式)を埋め込む" do
    get stats_path
    data = JSON.parse(css_select("script[data-genre-sunburst-target=data]").first.text)
    assert_equal [ "文学", "日本文学", "小説" ], data["labels"]
    assert_equal [ "L#{genres(:large_literature).id}", "M#{genres(:medium_japanese).id}", "S#{genres(:small_novel).id}" ], data["ids"]
    assert_equal [ "", "L#{genres(:large_literature).id}", "M#{genres(:medium_japanese).id}" ], data["parents"]
    assert_equal [ 1, 1, 1 ], data["values"]
    assert_equal [ genres(:large_literature).id, genres(:medium_japanese).id, genres(:small_novel).id ], data["genre_ids"]
  end

  test "読みの長さの30以上はまとめ棒になり、文字数側だけ範囲検索へリンクする" do
    word = Word.create!(surface: "とても長い開発語", annotated_at: Time.current, annotation_status: :done)
    word.word_senses.create!(reading: "ナ" * 35)

    get stats_path
    # 文字数の35は単独の棒にならず「30+」のまとめ棒(reading_length_min の範囲検索リンク)になる
    assert_select "a[href=?]", words_path(reading_length: 35), count: 0
    assert_select "a[href=?]", words_path(reading_length_min: 30)
    # モーラ側には範囲検索パラメータが無いため、まとめ棒はリンクにしない
    assert_select "g.wave-chart__bar--static", count: 1
  end

  test "特徴ランキングの実例は該当部分に朱下線の span を持つ" do
    get stats_path
    assert_select ".feature-rank__target", text: "殺人"
  end

  test "アノテーション依存の章には集計対象の語義数を明示する" do
    get stats_path
    assert_select ".stats-covered", text: I18n.t("stats.index.annotated_note", count: 1), minimum: 1
  end

  test "公開語が無ければ空表示にする(例外を出さない)" do
    Word.annotated.destroy_all
    get stats_path
    assert_response :success
    assert_select ".empty-note"
    assert_select "svg.wave-chart", count: 0
  end

  test "統計はヘッダー・フッター・sitemap・llms.txt からリンクされる" do
    get root_path
    assert_select "header a[href=?]", stats_path
    assert_select "footer a[href=?]", stats_path

    get sitemap_path
    assert_includes response.body, "/stats"

    get llms_path
    assert_includes response.body, "/stats"
  end
end
