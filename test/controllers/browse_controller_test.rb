require "test_helper"

# 50音・読みの長さの索引(/browse。Issue 22)。件数の集計は PublishedSenseCountsTest で見る。
class BrowseControllerTest < ActionDispatch::IntegrationTest
  test "索引は誰でも見られ(index 可)、公開語義のある文字・長さだけが件数つきで絞り込みへリンクする" do
    get browse_path
    assert_response :success
    assert_select "h1.page-title", text: I18n.t("browse.index.title")
    assert_select "meta[name=robots]", count: 0

    # カ(curry の読み カレー)→ 先頭文字の絞り込み。件数は50音表の整列を崩さないよう、
    # セルに文字で並べずヒートと title(ホバー)で示す
    assert_select "a.kana-cell--link[href=?]", words_path(first_char: "カ")
    assert_select "a.kana-cell--heat[href=?][title=?]", words_path(first_char: "カ"),
                  I18n.t("shared.kana_heat_grid.count_label", char: "カ", count: 1)
    # 公開語義が無い先頭文字はリンクにせず、沈めて表示する
    assert_select "a.kana-cell--link[href=?]", words_path(first_char: "ヲ"), count: 0
    assert_select ".kana-cell--muted", minimum: 1

    # 50音と読みの長さは、それぞれセグメントボタンで表を切り替える。切り替え先の表(末尾の文字・モーラ数)も
    # サーバが描いておき、JS が無いときは隠したまま既定の表だけを出す
    assert_select ".segmented .segmented__button[data-panel-key]", count: 4
    assert_select "[data-panel-key=first_char]:not([hidden]) .kana-grid"
    # 末尾の文字 レ(カレー)→ 末尾文字の絞り込み
    assert_select "[data-panel-key=last_char][hidden] a.kana-cell--heat[href=?]", words_path(last_char: "レ")

    # 読みの文字数 3(カレー)・7(さつじんじけん)→ 文字数の絞り込み。件数は「件」単位で条件の数字と区別する
    assert_select "[data-panel-key=reading_length]:not([hidden]) a.browse-length[href=?]", words_path(reading_length: 3),
                  text: /#{I18n.t("browse.index.length_unit.reading_length", count: 3)}/
    assert_select "a.browse-length[href=?]", words_path(reading_length: 7)
    assert_select ".browse-length__count", text: /\A\d+件\z/, minimum: 1
    # モーラ数 7(さつじんじけん)→ モーラ数の絞り込みと、数え方の注
    assert_select "[data-panel-key=mora_count][hidden]" do
      assert_select "a.browse-length[href=?]", words_path(mora_count: 7),
                    text: /#{I18n.t("browse.index.length_unit.mora_count", count: 7)}/
      assert_select ".browse-hint", text: I18n.t("browse.index.mora_hint")
    end
  end
end
