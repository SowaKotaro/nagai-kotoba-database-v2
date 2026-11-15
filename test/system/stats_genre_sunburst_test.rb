require "application_system_test_case"

class StatsGenreSunburstTest < ApplicationSystemTestCase
  # ジャンル別の語義数は、図も内訳も Stimulus(genre-sunburst)が描く。サーバのマークアップには現れないので、
  # 実ブラウザで押して確かめる。動きの途中は見ず、止まったあとの図と内訳だけを見る。
  setup do
    # フィクスチャの木(文学 › 日本文学 › 小説)に、同じ中分類の小分類と、別の中分類を足す
    literature = genres(:large_literature)
    japanese = genres(:medium_japanese)
    @novel = genres(:small_novel)
    @poetry = Genre.create!(name: "詩歌の検証", parent: japanese, level: :small)
    foreign = Genre.create!(name: "海外文学の検証", parent: literature, level: :medium)
    @translated = Genre.create!(name: "翻訳小説の検証", parent: foreign, level: :small)

    create_published_word(surface: "円環掘り下げ検証語一", reading: "エンカンホリサゲケンショウゴイチ", genre: @novel)
    create_published_word(surface: "円環掘り下げ検証語二", reading: "エンカンホリサゲケンショウゴニ", genre: @poetry)
    create_published_word(surface: "円環掘り下げ検証語三", reading: "エンカンホリサゲケンショウゴサン", genre: @translated)
  end

  test "扇と内訳の行で 1 階層ずつ掘り下げ、中心とパンくずで戻り、小分類のタグは単語一覧へつながる" do
    visit stats_path
    wait_for_stimulus("genre-sunburst")

    within ".genre-analysis" do
      root = I18n.t("stats.index.genre_map.root_label")
      total = WordSense.published.where.not(genre_id: nil).count

      # 初期表示: 中心は全体。大分類の行が 1 つで、扇は大分類と中分類の 2 階層
      assert_selector ".genre-crumbs [aria-current]", text: root
      assert_selector ".genre-sunburst__hub-count", text: total.to_s
      assert_selector ".genre-row", count: 1
      japanese_senses = WordSense.published.where(genre: [ @novel, @poetry ]).count
      assert_selector ".genre-sunburst__wedge", count: 3

      # 行を押すと大分類へ: 内訳は中分類の行(名前・語義数・割合)になり、パンくずが伸びる
      find(".genre-row", text: "文学").click
      assert_selector ".genre-crumbs [aria-current]", text: "文学"
      assert_selector ".genre-crumbs button", text: root
      row = find(".genre-row", text: "日本文学")
      assert_equal japanese_senses.to_s, row.find(".genre-row__count").text
      assert_selector ".genre-row", count: 2
      # 動きが止まると、扇は中分類 2 つと小分類 3 つになる
      assert_selector ".genre-sunburst__wedge", count: 5

      # 中分類の扇を押すと小分類へ: 内訳は件数つきのタグで、そのジャンルの単語一覧へつながる
      # (扇は弧なので、外接する矩形の真ん中を押すネイティブクリックは中心の円に当たる。click イベントを直に送る)
      wedge = find(".genre-sunburst__wedge[data-genre-sunburst-key-param='2-#{genres(:medium_japanese).id}']")
      page.execute_script("arguments[0].dispatchEvent(new MouseEvent('click', { bubbles: true }))", wedge)
      assert_selector ".genre-crumbs [aria-current]", text: "日本文学"
      assert_selector ".genre-rows--tags a.tag", count: 2
      assert_selector "a.tag[href='#{words_path(genre_id: @poetry.id)}']", text: "詩歌の検証"
      assert_no_selector ".genre-row"

      # 中心で 1 階層、パンくずで先頭へ戻る(中心は動きが止まってから現れる)
      find(".genre-sunburst__hub").click
      assert_selector ".genre-crumbs [aria-current]", text: "文学"
      click_button root
      assert_selector ".genre-crumbs [aria-current]", text: root
      assert_selector ".genre-row", count: 1
    end
  end
end
