require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  # 一括登録で下書きを作った日(created_at)と、注釈を終えて公開した日(annotated_at)は何日もずれる。
  # トップの「今月の新収録」と新着欄は「サイトに出てきた日」で数え、並べる。
  test "今月の新収録は公開日(annotated_at)で数え、下書きを作った月(created_at)では数えない" do
    Word.annotated.update_all(annotated_at: Time.current)
    get root_path
    assert_response :success
    assert_select ".stats-grid__item dt", text: I18n.t("home.index.stats.monthly_new")
    assert_select ".stats-grid__item dd", text: /\A2/

    Word.annotated.update_all(created_at: Time.current, annotated_at: 2.months.ago)
    get root_path
    assert_select ".stats-grid__item dd", text: /\A0/
  end

  test "最近追加された単語は公開日(annotated_at)で並び、その日付を表示する" do
    words(:abc_murder).update_columns(created_at: "2026-07-29 10:00:00", annotated_at: "2026-08-04 10:00:00")
    words(:curry).update_columns(created_at: "2026-08-03 10:00:00", annotated_at: "2026-08-03 10:00:00")

    get root_path
    assert_response :success
    recent = css_select(".home-column").first
    assert_equal [ "2026.08.04", "2026.08.03" ], recent.css(".home-column__meta").map(&:text)
    assert_operator recent.to_s.index(words(:abc_murder).surface), :<,
                    recent.to_s.index(words(:curry).surface)
  end

  # 看板の「最長の読み」は、下の「読みが長い言葉」の1位と同じ値でなければならない
  # (別々に数えると、片方だけ古い値が出て食い違う)。
  test "トップの最長ランキングは看板の最長の読みと一致し、ランキングページへの導線がある" do
    get root_path
    assert_response :success

    assert_select "h2.section-title .section-title__ja", text: I18n.t("home.index.ranking")
    # 公開(注釈済み)の語が並び、最長以外の番付はランキングページへ送る
    assert_select "a.home-column__item[href=?]", word_path(words(:abc_murder))
    assert_select "a[href=?]", rankings_path

    longest = css_select(".home-column").last.css(".home-column__meta").first.text
    figure = css_select(".stats-grid--rows .stats-grid__item")
             .find { |item| item.css("dt").text == I18n.t("home.index.stats.longest") }
    assert_not_nil figure, "看板に「最長の読み」の行がある"
    assert_equal longest.gsub(/[^0-9]/, ""), figure.css("dd").text.gsub(/[^0-9]/, "")
  end

  # いまは「読みが長い言葉」の並びは words.max_reading_length で決まるが、看板と行に出す数は
  # 先頭(id が最小)の語義の文字数。先頭の語義が最長でない語では、並びの指標と出る数がずれる(いまの振る舞い)。
  test "多語義語が最長のとき、看板と「読みが長い言葉」の数は先頭の語義の文字数" do
    word = Word.new(surface: "代表語義の見本")
    word.word_senses.build(reading: "ミジカイヨミ")                 # 6 字・id が小さい
    word.word_senses.build(reading: "トテモナガイヨミノゴギデスヨネ") # 15 字
    word.mark_annotated
    word.save!

    get root_path
    first_item = css_select(".home-column").last.css(".home-column__item").first
    assert_equal word_path(word), first_item["href"]
    assert_equal I18n.t("words.index.char_count", count: 6), first_item.css(".home-column__meta").text
    figure = css_select(".stats-grid--rows .stats-grid__item")
             .find { |item| item.css("dt").text == I18n.t("home.index.stats.longest") }
    assert_equal "6", figure.css("dd").text.gsub(/[^0-9]/, "")
  end

  # 公開クエリ名 q は世に出ているので変えない(CLAUDE.md)。
  test "ホームの検索欄は単語一覧へ q を GET で送る" do
    get root_path
    assert_select "form.hero-search[action=?][method=get] input[name=q]", words_path
  end

  test "今日の一語は日付で決まり、翌日は別の語になる" do
    ordered = Word.annotated.order(:id).to_a
    assert_equal 2, ordered.size, "フィクスチャの公開語は2語の前提"
    date = Date.new(2026, 10, 1)
    date += 1 until date.jd.even?

    travel_to(date.in_time_zone.change(hour: 12)) { get root_path }
    assert_select ".home-featured a.home-featured__more[href=?]", word_path(ordered[0])

    travel_to((date + 1).in_time_zone.change(hour: 12)) { get root_path }
    assert_select ".home-featured a.home-featured__more[href=?]", word_path(ordered[1])
  end

  # 語数はホームの統計と一緒にキャッシュしている。公開・保留の直後でキャッシュの語数と実際の語数が
  # ずれていても、今日の一語はキャッシュの語数で選ぶ(数え直すと COUNT が毎リクエストに戻る)。
  test "今日の一語は、キャッシュした語数で選ぶ(実際の語数とずれていても)" do
    ordered = Word.annotated.order(:id).to_a
    # 2 語なら先頭、3 語なら 2 番目を選ぶ日(jd % 2 == 0 かつ jd % 3 == 1)
    date = Date.new(2026, 10, 1)
    date += 1 until date.jd % 6 == 4

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    travel_to(date.in_time_zone.change(hour: 12)) do
      get root_path
      assert_select ".home-featured a.home-featured__more[href=?]", word_path(ordered[0])

      word = Word.new(surface: "今日の一語の語数ずれの見本")
      word.word_senses.build(reading: "キョウノイチゴノゴスウズレノミホン")
      word.mark_annotated
      word.save!
      assert_equal 3, Word.annotated.count

      get root_path
      assert_select ".home-featured a.home-featured__more[href=?]", word_path(ordered[0])
    end
  ensure
    Rails.cache = original_cache
  end
end
