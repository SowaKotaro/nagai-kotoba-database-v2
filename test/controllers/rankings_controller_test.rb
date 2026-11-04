require "test_helper"

# ランキングのハブ(/rankings)。各枠の組の作り方と載せる語は WordRankingTest で見る。
class RankingsControllerTest < ActionDispatch::IntegrationTest
  # 公開語が TOP_LIMIT 件を超えないと、どの枠も順位表として成立しない(WordRanking#board)。
  # 濁点・小書き・長音を含まない読みで足すので、長さの枠は出て、濁点・語義数などの枠は出ない。
  setup do
    WordRanking::TOP_LIMIT.times do |i|
      create_published_word(surface: "順位の母集団#{i}", reading: "ナナナナナ" + "ア" * i)
    end
  end

  test "ランキングは誰でも見られ、成立する枠だけを並べ、行は同じ値の組ごとに順位・代表の見出し語・指標値・単位を持つ" do
    # 長音符 2 本の組を、畳む語の上限(FOLD_LIMIT)より 1 語多く作る(長音符 1 本の カレー は組の後ろで載らない)
    (WordRanking::FOLD_LIMIT + 2).times { |i| create_published_word(surface: "長音二本#{i}", reading: "ナーナー") }

    get rankings_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("rankings.index.title")
    # リードは文ごとに行を分ける(文節の折り方は WordsControllerTest の 0 件の案内で見る)
    assert_select "p.page-lead .phrase-sentence", count: I18n.t("rankings.index.lead").size
    assert_select "meta[name=robots]", count: 0

    expected = WordRanking.all.count { |ranking| ranking.board.any? }
    assert_operator expected, :>, 0
    assert_select "section.rank-panel", count: expected
    assert_select ".rank-tab", count: expected
    # 先頭のタブだけが押された状態で、パネルはサーバ側では隠さない(JS 無効でも全部読める)
    assert_select ".rank-tab[aria-pressed=true]", count: 1
    assert_select "[data-panel-switch-target=panel][hidden]", count: 0

    # 該当語が TOP_LIMIT 件以下の枠(ここでは語義が複数・濁点)は出さない
    assert_select "#rank-sense-count-desc", count: 0
    assert_select "#rank-dakuten-desc", count: 0

    # 各枠の「もっと見る」は同じ並びの単語一覧へ。遷移先は必ず noindex(同じ集合の順列違い)なので nofollow
    assert_select ".rank-panel__more[href=?]", words_path(sort: "length_desc")
    assert_select ".rank-panel__more[rel=nofollow]", count: expected

    # 行は値の違う組ごとに 1 つで、上から TOP_LIMIT 組。読み 7 字は ABC殺人事件(さつじんじけん) と 母集団2 の 2 語で 1 組
    assert_select "#rank-length-desc .rank-row", count: WordRanking::TOP_LIMIT
    assert_select "#rank-length-desc .rank-row:first-child" do
      assert_select ".rank-row__no", text: "1"
      # 最長は「ナナナナナ + ア×9」の 14 字
      assert_select "a.rank-row__surface", text: "順位の母集団9"
      assert_select ".rank-row__number", text: "14"
      assert_select ".rank-row__unit", text: I18n.t("rankings.boards.length_desc.unit")
      assert_select ".rank-fold", count: 0
    end
    # 組のほかの語は「ほかN語」に畳み、各語の詳細へリンクする
    assert_select "#rank-length-desc .rank-fold" do
      assert_select ".rank-fold__summary", text: I18n.t("rankings.board.others", count: 1)
      assert_select ".rank-fold__list a[href=?]", word_path(Word.find_by!(surface: "順位の母集団2")), text: "順位の母集団2"
      assert_select ".rank-fold__rest", count: 0
    end
    # 畳む語が上限を超えた組は、残りの語数を示して同じ並びの一覧へ渡す(nofollow は「もっと見る」と同じ理由。
    # 組が始まるページの選び方は RankingsHelperTest で見る)
    assert_select "#rank-chouon-desc .rank-fold" do
      assert_select ".rank-fold__summary", text: I18n.t("rankings.board.others", count: WordRanking::FOLD_LIMIT + 1)
      assert_select ".rank-fold__list li", count: WordRanking::FOLD_LIMIT
      assert_select ".rank-fold__rest[href=?][rel=nofollow]", words_path(sort: "chouon_desc"),
                    text: I18n.t("rankings.board.rest", count: 1)
    end
  end
end
