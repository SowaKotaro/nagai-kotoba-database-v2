require "test_helper"

# ランキングのハブ(/rankings)。各枠の順位の出し方と載せる語は WordRankingTest で見る。
class RankingsControllerTest < ActionDispatch::IntegrationTest
  # 公開語が TOP_LIMIT 件を超えないと、どの枠も順位表として成立しない(WordRanking#board)。
  # 濁点・小書き・長音を含まない読みで足すので、長さの枠は出て、濁点・語義数などの枠は出ない。
  setup do
    WordRanking::TOP_LIMIT.times do |i|
      word = Word.create!(surface: "順位の母集団#{i}", annotated_at: Time.current)
      word.word_senses.create!(reading: "ナナナナナ" + "ア" * i)
    end
  end

  test "ランキングは誰でも見られ、順位表として成立する枠だけをタブと同じ数だけ並べる" do
    get rankings_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("rankings.index.title")
    assert_select "meta[name=robots]", count: 0

    expected = WordRanking.all.count { |ranking| ranking.board.any? }
    assert_operator expected, :>, 0
    assert_select "section.rank-board", count: expected
    assert_select ".rank-tab", count: expected
    # 先頭のタブだけが押された状態で、パネルはサーバ側では隠さない(JS 無効でも全部読める)
    assert_select ".rank-tab[aria-pressed=true]", count: 1
    assert_select "[data-panel-switch-target=panel][hidden]", count: 0

    # 該当語が少なく全員が載ってしまう枠(ここでは語義が複数・濁点)は出さない
    assert_select "#rank-sense-count-desc", count: 0
    assert_select "#rank-dakuten-desc", count: 0

    # 各枠の「もっと見る」は同じ並びの単語一覧へ。遷移先は必ず noindex(同じ集合の順列違い)なので nofollow
    assert_select ".rank-board__more[href=?]", words_path(sort: "length_desc")
    assert_select ".rank-board__more[rel=nofollow]", count: expected
  end

  test "行は順位・見出し語・指標値・単位を持ち、上位3位には印が付く" do
    get rankings_path
    assert_select "#rank-length-desc .rank-row", count: WordRanking::TOP_LIMIT
    assert_select "#rank-length-desc .rank-row:first-child" do
      assert_select ".rank-row__no.rank-row__no--top", text: "1"
      # 最長は「ナナナナナ + ア×9」の 14 字
      assert_select "a.rank-row__surface", text: "順位の母集団9"
      assert_select ".rank-row__number", text: "14"
      assert_select ".rank-row__unit", text: I18n.t("rankings.boards.length_desc.unit")
    end
  end
end
