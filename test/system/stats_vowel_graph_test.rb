require "application_system_test_case"

class StatsVowelGraphTest < ApplicationSystemTestCase
  # 母音の遷移グラフの2つの操作を実ブラウザで確かめる。
  #   - 「多い遷移だけ表示」: checkbox + 兄弟セレクタの CSS だけで動く(JS を持たない)
  #   - ノードを押して並びを選び、検索へ: Stimulus(vowel-graph)
  # どちらも表示側で完結していて壊れても気づきにくいので、押して確かめる。
  setup do
    # 少ない遷移(その区間の 6% 未満)が生まれるだけの語義を用意する。
    # 20 語義あれば1本しか通らない組は 5% になり、伏せる対象になる。
    word = Word.create!(surface: "母音遷移の検証語", annotated_at: Time.current, annotation_status: :done)
    readings = %w[ア イ ウ エ オ カ キ ク ケ コ サ シ ス セ ソ タ チ ツ テ ト]
    readings.each_with_index do |head, index|
      word.word_senses.create!(reading: "#{head}カサタナハマヤラワ#{readings[(index + 3) % readings.size]}")
    end
    Rails.cache.delete(SiteStatistics::CACHE_KEY)
  end

  teardown { Rails.cache.delete(SiteStatistics::CACHE_KEY) }

  test "「多い遷移だけ表示」で少ない遷移だけが伏せられる" do
    visit stats_path

    assert_selector ".vowel-graph__edge.is-faint", visible: true, minimum: 1
    strong = all(".vowel-graph__edge:not(.is-faint)", visible: true).size
    assert_operator strong, :>, 0

    click_expecting(expect_css: ".vowel-graph__edge.is-faint", visible: true, count: 0) do
      find(".vowel-graph-panel__switch")
    end

    # 多い遷移はそのまま残る(全部消えてしまっては図にならない)
    assert_selector ".vowel-graph__edge:not(.is-faint)", visible: true, count: strong
  end

  # 選び方の決まり(vowel_graph_controller.js): 鎖の端の隣を押せば伸び、離れた拍は鎖を残したまま
  # 「控え」として選ぶ。あいだが埋まれば控えまで繋ぎ、控えの隣が決まったときに初めて鎖を引き直す。
  test "ノードを押し継いで母音の並びを選び、その並びの検索へ進める" do
    visit stats_path
    wait_for_stimulus("vowel-graph")
    assert_no_selector ".vowel-graph-panel__readout", visible: true

    # 1つ目は選ぶだけ。導線は2つ目を押してから出る
    node(1, "a").click
    assert_no_selector ".vowel-graph-panel__readout", visible: true
    node(2, "a").click
    assert_selector ".vowel-graph-panel__readout", visible: true
    assert_picked nodes: 2, edges: 1

    # 離れた拍(4)は控え。あいだが後から埋まるかもしれないので鎖は消さない
    node(4, "a").click
    assert_picked nodes: 3, edges: 1

    # あいだの 3 を埋めると、控えの 4 まで一続きになる
    node(3, "a").click
    assert_picked nodes: 4, edges: 3
    assert_selector ".vowel-graph-panel__link[href$='vowel_transition=1-aaaa']"

    # また離れた拍(6)を押しても鎖は残り、その隣(7)が決まって初めて新しい鎖に引き直す
    node(6, "a").click
    assert_picked nodes: 5, edges: 3
    node(7, "a").click
    assert_picked nodes: 2, edges: 1
    assert_selector ".vowel-graph-panel__link[href$='vowel_transition=6-aa']"

    find(".vowel-graph-panel__link").click
    assert_current_path words_path(vowel_transition: "6-aa")
    assert_text I18n.t("searches.vowel_transition")
  end

  private

  def node(position, vowel)
    find(".vowel-graph__node[data-position='#{position}'][data-vowel='#{vowel}']")
  end

  def assert_picked(nodes:, edges:)
    assert_selector ".vowel-graph__node.is-picked", count: nodes, visible: :all
    assert_selector ".vowel-graph__edge.is-selected", count: edges, visible: :all
  end
end
