require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  # 一括登録で下書きを作った日(created_at)と、注釈を終えて公開した日(annotated_at)は何日もずれる。
  # トップの新着欄は「サイトに出てきた日」で並べ、その日付を出す。
  test "最近追加された単語は公開日(annotated_at)で並べる" do
    words(:abc_murder).update_columns(created_at: "2026-07-29 10:00:00", annotated_at: "2026-08-04 10:00:00")
    words(:curry).update_columns(created_at: "2026-08-03 10:00:00", annotated_at: "2026-08-03 10:00:00")

    get root_path
    assert_response :success
    recent = css_select(".home-column").first
    assert_equal [ "2026.08.04", "2026.08.03" ], recent.css(".home-column__meta").map(&:text)
    assert_operator recent.to_s.index(words(:abc_murder).surface), :<,
                    recent.to_s.index(words(:curry).surface)
  end

  test "看板の検索欄と探し方の入口は各ページと絞り込みへ送り、読みが長い言葉は先頭の語義の文字数を出す" do
    # フィクスチャの公開語は読みが 10 字に満たないので、読みの長さの選択肢が出るよう 15 字の公開語を足す
    create_published_word(surface: "十五字の見本", reading: "アイウエオカキクケコサシスセソ")
    get root_path
    assert_response :success

    # 説明は文ごとに行を分け、文節の切れ目でだけ折る(.phrase-sentence)。分けても文言は欠けない
    assert_equal I18n.t("home.index.description").size, css_select(".hero__lead .phrase-sentence").size
    assert_equal I18n.t("home.index.description").join, css_select(".hero__lead").text

    # ホームの検索欄は単語一覧へ q を GET で送る
    # 公開クエリ名 q は世に出ているので変えない(CLAUDE.md)。案内は例文を添えない短い文言(スマホで切れるため)
    assert_select "form.hero-search[action=?][method=get] input[name=q][placeholder=?]", words_path, I18n.t("layouts.search_placeholder")
    # 検索欄の下の探し方の入口は、選択肢が開くボタン → 索引・ランダム・詳細検索へ進むボタン(HomeHelper#home_search_ways)
    assert_equal %w[search-way-genre search-way-entity-type search-way-linguistic-feature search-way-reading-length
                    search-way-word-origin search-way-part-of-speech],
                 css_select(".search-ways__toggle").map { |button| button["aria-controls"] }
    # 読みの長さの選択肢は、19 文字までは 1 文字ずつ(15〜19 のようにまとめない。20 文字以上は下の多語義語の見本で見る)
    assert_select "#search-way-reading-length a[href=?]", words_path(reading_length: 15),
                  text: I18n.t("home.index.ways.length.exact", count: 15)
    assert_equal [ browse_path, random_words_path, search_path ], css_select(".search-ways > a.search-ways__item").map { |link| link["href"] }
    # ランダムは押すたびに行き先が変わるので、検索エンジンには辿らせない
    assert_select ".search-ways > a[href=?][rel=nofollow]", random_words_path
    # 選択肢は単語一覧の絞り込みで、探すページを持つ探し方だけが末尾にそのページへのリンクを添える
    assert_select "#search-way-genre a[href=?]", words_path(genre_id: genres(:large_literature).id), text: genres(:large_literature).name
    assert_select "#search-way-genre a.search-ways__more[href=?]", genres_path
    assert_select "#search-way-word-origin a.search-ways__more", count: 0

    # 数字で見る長い言葉は、天井無しに増えていく数だけを、統計ページの章(数字の壁・収録の推移)へのリンクにして並べる。
    # 語と単位は統計ページの数字の壁と同じ
    assert_equal %w[timeline number-wall number-wall number-wall number-wall timeline].map { |anchor| stats_path(anchor:) },
                 css_select(".home-figures__item").map { |link| link["href"] }
    assert_select ".home-figures__item[href=?]", stats_path(anchor: "timeline"),
                  text: /#{I18n.t("stats.index.wall.scale.words")}\s*3#{I18n.t("stats.index.unit.words")}/
    assert_select ".home-figures a.panel__more[href=?]", stats_path

    assert_select "h2.panel__title", text: I18n.t("home.index.ranking")
    # 公開(注釈済み)の語が並び、最長以外の番付はランキングページへ送る
    assert_select "a.home-column__item[href=?]", word_path(words(:abc_murder))
    assert_select "a[href=?]", rankings_path

    # 多語義語が最長のとき、「読みが長い言葉」の行に出す数は先頭の語義の文字数
    # いまは並びは words.max_reading_length で決まるが、行に出す数は先頭(id が最小)の語義の文字数。
    # 先頭の語義が最長でない語では、並びの指標と出る数がずれる(いまの振る舞い)。
    word = Word.new(surface: "代表語義の見本")
    word.word_senses.build(reading: "ミジカイヨミ")                 # 6 字・id が小さい
    word.word_senses.build(reading: "トテモナガイヨミノゴギデスヨネホントニネエ") # 21 字
    word.mark_annotated
    word.save!

    get root_path
    first_item = css_select(".home-column").last.css(".home-column__item").first
    assert_equal word_path(word), first_item["href"]
    assert_equal "6", first_item.css(".home-column__number").text
    # 20 文字以上はまとめて、下限だけで絞る
    assert_select "#search-way-reading-length a[href=?]", words_path(reading_length_min: 20),
                  text: I18n.t("home.index.ways.length.at_least", min: 20)
  end

  test "探し方の入口は描いた結果を使い回し、選択肢が変わったときだけ描き直す" do
    with_fragment_cache do
      get root_path
      assert_select "#search-way-reading-length", count: 0

      # 読みが 10 字以上の公開語が付くと選択肢が変わり、読みの長さのボタンが出る
      create_published_word(surface: "十五字の見本", reading: "アイウエオカキクケコサシスセソ")
      get root_path
      assert_select "#search-way-reading-length a[href=?]", words_path(reading_length: 15)
    end
  end

  test "今日の一語は日付とキャッシュした語数で決まる" do
    ordered = Word.annotated.order(:id).to_a
    assert_equal 2, ordered.size, "フィクスチャの公開語は2語の前提"
    date = Date.new(2026, 10, 1)
    date += 1 until date.jd.even?

    travel_to(date.in_time_zone.change(hour: 12)) { get root_path }
    assert_select ".home-featured a.panel__more[href=?]", word_path(ordered[0])

    travel_to((date + 1).in_time_zone.change(hour: 12)) { get root_path }
    assert_select ".home-featured a.panel__more[href=?]", word_path(ordered[1])

    # 語数は毎リクエスト COUNT を打たないよう 1 時間キャッシュする(HomeStatistics。Issue 26)。
    # 公開・保留の直後でキャッシュの語数と実際の語数がずれていても、1 時間のうちはキャッシュの語数で選び
    # (数え直すと COUNT が毎リクエストに戻る)、期限が切れたら数え直す。
    # 2 語なら先頭、3 語なら 2 番目を選ぶ日(jd % 2 == 0 かつ jd % 3 == 1)
    date = Date.new(2026, 10, 1)
    date += 1 until date.jd % 6 == 4

    with_rails_cache do
      travel_to(date.in_time_zone.change(hour: 12)) do
        get root_path
        assert_select ".home-featured a.panel__more[href=?]", word_path(ordered[0])

        create_published_word(surface: "今日の一語の語数ずれの見本", reading: "キョウノイチゴノゴスウズレノミホン")
        assert_equal 3, Word.annotated.count

        travel 59.minutes
        get root_path
        assert_select ".home-featured a.panel__more[href=?]", word_path(ordered[0])

        travel 2.minutes
        get root_path
        assert_select ".home-featured a.panel__more[href=?]", word_path(ordered[1])
      end
    end
  end
end
