require "application_system_test_case"

class RankingsTest < ApplicationSystemTestCase
  # ランキングは種類が多いので、タブで1つずつ切り替えて見せる(縦に積むとページが長くなる)。
  # サーバは全パネルを描画しておき、JS が繋がった時点で初期表示へ畳む。
  # 「もっと見る」のリンク先は RankingsControllerTest で見る。
  #
  # 枠は該当語が TOP_LIMIT 件を超えないと出ない(WordRanking#board)ので、濁点を含む読みの語を足す。
  setup do
    WordRanking::TOP_LIMIT.times do |i|
      word = Word.create!(surface: "順位の母集団#{i}", annotated_at: Time.current)
      word.word_senses.create!(reading: "ガガガガガ" + "ア" * i)
    end
  end

  test "ランキングはタブで切り替わり、初期表示は先頭の1つだけ" do
    visit rankings_path
    wait_for_stimulus("panel-switch")

    assert_selector "#rank-length-desc"
    assert_no_selector "#rank-dakuten-desc"

    click_expecting(expect_css: "#rank-dakuten-desc") do
      find(".rank-tab", text: I18n.t("rankings.boards.dakuten_desc.title"))
    end
    assert_no_selector "#rank-length-desc"
    # 押されたタブだけが現在地になる
    assert_selector ".rank-tab[aria-pressed='true']", count: 1
  end
end
