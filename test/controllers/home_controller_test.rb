require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "未認証でもトップページを閲覧できる" do
    get root_path
    assert_response :success
  end

  test "収録統計に今月の新収録数を出す" do
    # 「今月の新収録」は annotated_at(公開日)で数えるので、公開語2語を今月に寄せる。
    Word.annotated.update_all(annotated_at: Time.current)

    get root_path
    assert_select ".stats-grid__item dt", text: I18n.t("home.index.stats.monthly_new")
    assert_select ".stats-grid__item dd", text: /\A2/
  end

  # 一括登録で下書きを作った日(created_at)と、注釈を終えて公開した日(annotated_at)は
  # 何日もずれる。新着欄は「サイトに出てきた日」を見せる。
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

  test "今月の新収録は下書きを作った月(created_at)では数えない" do
    Word.annotated.update_all(created_at: Time.current, annotated_at: 2.months.ago)

    get root_path
    assert_select ".stats-grid__item dd", text: /\A0/
  end

  test "トップに最長ランキングと、ランキングページへの導線がある" do
    get root_path
    assert_response :success
    assert_select "h2.home-column__title", text: /#{Regexp.escape(I18n.t("home.index.ranking"))}/
    # 最長以外の番付も束ねたランキングページへ送る(全順位はその先の「もっと見る」から)
    assert_select "a[href=?]", rankings_path
    # 公開(注釈済み)の語がランキングに並ぶ
    assert_select "a.home-column__item[href=?]", word_path(words(:abc_murder))
  end
end
