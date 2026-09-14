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
end
