require "test_helper"

class SnsPostTextTest < ActiveSupport::TestCase
  test "本文は表層形と読み(文字数つき)で、X の上限(和文 1 字を 2 と数える)に収まる語だけを出す" do
    word = create_published_word(surface: "寿限無寿限無五劫の擦り切れ", reading: "ジュゲムジュゲムゴコウノスリキレ", meaning: "落語の長い名前")
    assert_equal "寿限無寿限無五劫の擦り切れ\nジュゲムジュゲムゴコウノスリキレ（16文字）", SnsPostText.body(word)
    assert SnsPostText.fits?(word)

    # 英字と記号は 1、和文と全角の括弧は 2
    assert_equal 2 + 1 + 4, SnsPostText.x_weight("AB\nあい")

    # 表層形 70 字＋読み 70 字で、和文 140 字(重み 280)を超える
    long = create_published_word(surface: "長" * 70, reading: "ナ" * 70)
    assert_not SnsPostText.fits?(long)
  end

  test "返信のリンクは単語詳細の絶対 URL で、カードの題は表層形、説明は意味" do
    word = create_published_word(surface: "寿限無寿限無五劫の擦り切れ", reading: "ジュゲムジュゲムゴコウノスリキレ", meaning: "落語の\n長い名前")
    link = SnsPostText.message(word, image: "png").link

    assert_equal "#{CANONICAL_HOST}/words/#{word.id}", link.url
    assert_equal [ "寿限無寿限無五劫の擦り切れ", "落語の 長い名前", "png" ], [ link.title, link.description, link.image ]
  end
end
