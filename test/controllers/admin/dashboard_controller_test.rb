require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "認証済みなら収録状況と各作業への導線を表示する" do
    sign_in_as(Admin.take)
    get admin_root_path
    assert_response :success

    # 統計(総数・注釈済み・未注釈)
    assert_select ".stats-grid__item", minimum: 3
    # 注釈の進捗(フィクスチャは 5 語中 2 語が注釈済み)
    assert_select ".admin-meter__value", text: "40%"
    # 作業のカードは共通ナビと同じ並び(ナビ先頭のダッシュボード自身を除く)
    nav_paths = css_select(".admin-nav a").map { |link| link["href"] } - [ admin_root_path ]
    assert_equal nav_paths, css_select(".admin-card__link").map { |link| link["href"] }
    # アノテーションのカードには、まとめて注釈(デッキ)への近道を添える
    assert_select ".admin-card a[href=?]", admin_annotation_deck_path
    # 未注釈の残数を「要対応」として表示する
    assert_select ".admin-card__meta--pending > span",
      text: I18n.t("admin.dashboard.sections.annotations.meta", count: Word.unannotated.count)
  end

  test "単語が 1 語も無くても表示でき、注釈の進捗は 0% になる" do
    Word.destroy_all
    sign_in_as(Admin.take)
    get admin_root_path
    assert_response :success

    assert_select ".admin-meter__value", text: "0%"
  end
end
