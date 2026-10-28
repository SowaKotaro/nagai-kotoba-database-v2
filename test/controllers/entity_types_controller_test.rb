require "test_helper"

# エンティティから探すページ(/entity_types)。件数の集計は PublishedSenseCountsTest、
# 名前で絞り込む欄の動き(JS)は SearchHubsTest(system)で見る。
class EntityTypesControllerTest < ActionDispatch::IntegrationTest
  test "誰でも見られ(index 可)、公開語義のあるエンティティだけを語の多い順に件数つきで絞り込みへリンクする" do
    # 人名を 2 語公開して、書籍名(ABC殺人事件の 1 語)より前に並ぶことを見る
    2.times { |i| create_published_word(surface: "人名の語#{i}", reading: "ジンメイノゴ#{i}", entity_type: entity_types(:person_name)) }

    get entity_types_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("entity_types.index.title")
    assert_select "meta[name=robots]", count: 0

    assert_select "[data-controller=list-filter]" do
      assert_select ".list-filter[hidden] input[type=search][aria-label=?]", I18n.t("entity_types.index.filter_label")
      tags = css_select("li[data-list-filter-target=item] a.entity-hub__tag")
      assert_equal [ words_path(entity_type_id: entity_types(:person_name).id), words_path(entity_type_id: entity_types(:book_title).id) ],
                   tags.map { |tag| tag["href"] }
      assert_equal [ "人名 2", "書籍名 1" ], tags.map { |tag| tag.text.squish }
    end
  end
end
