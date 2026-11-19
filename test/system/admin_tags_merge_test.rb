require "application_system_test_case"

# タグの統合で、統合元・統合先を名前で絞り込み、統合先を統合元と同じ階層に絞る(tag_merge_controller.js)。
# 統合そのもの(付け替えと削除)は Admin::TagsControllerTest と Genre のモデルテストで見る。
class AdminTagsMergeTest < ApplicationSystemTestCase
  setup { system_sign_in }

  test "統合元を名前で絞って選ぶと、統合先には同じ階層のほかのジャンルだけが並び、名前でさらに絞れる" do
    Genre.create!(name: "詩", parent: genres(:medium_japanese), level: :small)
    Genre.create!(name: "戯曲", parent: genres(:medium_japanese), level: :small)

    visit admin_tag_kind_path("genres")
    open_details("details.tag-merge")
    wait_for_stimulus "tag-merge"

    within "form[data-controller='tag-merge']" do
      # 統合元: 空白で区切ると、両方を含むものに絞る
      find("[data-tag-merge-target='sourceQuery']").fill_in(with: "日本文学 小説")
      assert_selector "#source_id option", count: 1
      find("#source_id option", text: /小説/).select_option

      # 統合先: 小分類のうち統合元(小説)を除いたものだけ
      assert_selector "#target_id option", count: 2
      assert_no_selector "#target_id option", text: "小説"
      assert_no_selector "#target_id option", text: /\A文学（/

      find("[data-tag-merge-target='targetQuery']").fill_in(with: "存在しない名前")
      assert_selector "#target_id option[disabled]", text: I18n.t("admin.tags.merge.no_match")
      find("[data-tag-merge-target='targetQuery']").fill_in(with: "戯曲")
      assert_selector "#target_id option", count: 1, text: "戯曲"
    end
  end
end
