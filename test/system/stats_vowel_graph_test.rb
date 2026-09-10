require "application_system_test_case"

class StatsVowelGraphTest < ApplicationSystemTestCase
  # 母音の遷移グラフの2つの操作を実ブラウザで確かめる。
  #   - 「多い遷移だけ表示」: checkbox + 兄弟セレクタの CSS だけで動く(JS を持たない)
  #   - ノードを2つ押して検索へ: Stimulus(vowel-graph)
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

  def node(position, vowel)
    find(".vowel-graph__node[data-position='#{position}'][data-vowel='#{vowel}']")
  end

  test "隣り合うノードを押し継ぐと並びが伸び、その並びの検索へ進める" do
    visit stats_path
    wait_for_stimulus("vowel-graph")

    assert_no_selector ".vowel-graph-panel__readout", visible: true

    # 1つ目は選ぶだけ。導線は2つ目を押してから出る
    node(1, "a").click
    assert_no_selector ".vowel-graph-panel__readout", visible: true
    node(2, "a").click

    assert_selector ".vowel-graph-panel__readout", visible: true
    assert_selector ".vowel-graph__edge.is-selected", count: 1, visible: :all
    assert_selector ".vowel-graph__node.is-picked", count: 2, visible: :all

    # 隣へ押し継ぐと鎖が伸びる(線も1本増える)
    node(3, "a").click
    assert_selector ".vowel-graph__edge.is-selected", count: 2, visible: :all
    assert_selector ".vowel-graph__node.is-picked", count: 3, visible: :all

    find(".vowel-graph-panel__link").click
    assert_current_path words_path(vowel_transition: "1-aaa")
    assert_text I18n.t("searches.vowel_transition")
  end

  test "鎖と控えのあいだを埋めると、両側とつながって一続きになる" do
    visit stats_path
    wait_for_stimulus("vowel-graph")

    node(1, "a").click
    node(2, "a").click
    node(4, "a").click # 離れた拍。ここではまだ控え
    assert_selector ".vowel-graph__edge.is-selected", count: 1, visible: :all

    # あいだの 3 を埋めたら、控えの 4 まで一続きになる
    node(3, "a").click
    assert_selector ".vowel-graph__node.is-picked", count: 4, visible: :all
    assert_selector ".vowel-graph__edge.is-selected", count: 3, visible: :all
    assert_selector ".vowel-graph-panel__link[href$='vowel_transition=1-aaaa']"
  end

  test "離れたノードを押しても鎖は消えず、そこから2つ目が決まって初めて引き直す" do
    visit stats_path
    wait_for_stimulus("vowel-graph")

    node(1, "a").click
    node(2, "a").click
    assert_selector ".vowel-graph__edge.is-selected", count: 1, visible: :all

    # 離れた拍。あいだが後から埋まるかもしれないので、鎖はそのまま
    node(6, "a").click
    assert_selector ".vowel-graph__edge.is-selected", count: 1, visible: :all
    assert_selector ".vowel-graph__node.is-picked", count: 3, visible: :all

    # 離れた拍の隣が決まった時点で、古い鎖を捨てて新しい鎖にする
    node(7, "a").click
    assert_selector ".vowel-graph__edge.is-selected", count: 1, visible: :all
    assert_selector ".vowel-graph__node.is-picked", count: 2, visible: :all
    assert_selector ".vowel-graph-panel__link[href$='vowel_transition=6-aa']"
  end

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
end
