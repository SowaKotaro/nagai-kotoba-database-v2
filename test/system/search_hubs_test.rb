require "application_system_test_case"

# 詳細検索から切り出した探し方のページ(ジャンル・エンティティ)の、名前で絞り込む欄(list_filter_controller.js)。
# 欄は JS がつながってから出る。ジャンルとエンティティは同じコントローラなので、束(group)と折り畳みを持つジャンルで見る。
# 欄の有無と絞り込みの手がかり(data 属性)は GenresControllerTest・EntityTypesControllerTest で見る。
class SearchHubsTest < ApplicationSystemTestCase
  # フィクスチャの 文学 › 日本文学 › 小説(ABC殺人事件)に加えて、別の大分類に公開語のある小分類を 2 つ置く
  setup do
    large = Genre.create!(name: "芸術", level: :large)
    medium = Genre.create!(name: "映画・アニメーション", parent: large, level: :medium)
    { "テレビアニメ" => "テレビアニメノゴ", "時代劇" => "ジダイゲキノゴ" }.each do |name, reading|
      small = Genre.create!(name: name, parent: medium, level: :small)
      create_published_word(surface: "#{name}の語", reading: reading, genre: small)
    end
  end

  test "ジャンルは名前で絞り込め、当たった分類の大分類だけが開き、欄を空にすると元に戻る" do
    visit genres_path
    wait_for_stimulus("list-filter")
    filter = find(".list-filter input[type=search]")

    # ひらがなで打ってもカタカナの名前に当たる。当たった小分類を含む大分類だけが開き、ほかの大分類は隠れる
    filter.fill_in(with: "てれびあに")
    within "details[open]", text: "芸術" do
      assert_selector "a.genre-hub__small", text: "テレビアニメ"
      assert_no_selector "a.genre-hub__small", text: "時代劇"
    end
    assert_no_selector ".genre-hub__large-name", text: "文学"

    # 中分類の名前に当たれば、その配下の小分類がすべて残る
    filter.fill_in(with: "アニメーション")
    assert_selector "a.genre-hub__small", text: "時代劇"

    # 何にも当たらなければ一言を出す
    filter.fill_in(with: "存在しない分類")
    assert_selector ".list-filter__empty", text: I18n.t("genres.index.filter_empty")
    assert_no_selector "details.genre-hub__fold"

    # 欄を空にすると、すべての大分類が畳んだ状態で戻る(絞り込みで開いたものは閉じ直す)
    filter.fill_in(with: "")
    assert_selector ".genre-hub__large-name", text: "文学"
    assert_selector "details.genre-hub__fold", count: 2
    assert_no_selector "details.genre-hub__fold[open]"
    assert_no_selector ".list-filter__empty"
  end
end
