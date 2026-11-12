require "test_helper"

# llms-full.txt の実物を読めることは LlmsControllerTest が確かめる。ここは書式が崩れたときの扱い。
class ResearchCorpusTest < ActiveSupport::TestCase
  test "見出し語と語義ごとの読みを拾い、冒頭の語数と見出しの数が合わなければ読めなかった扱いにする" do
    text = <<~TEXT
      公開している全 2 語の内容を、1ファイルにまとめています。

      ## 収録データ

      ### 殺人事件
      - 読み: サツジンジケン(7字 / 7拍)
      - 別表記: さつじん事件(サツジンジケン)

      ### カレー
      #### 語義1
      - 読み: カレー(3字 / 3拍)
      #### 語義2
      - 読み: カレーライス(6字)
    TEXT

    entries = ResearchCorpus.parse(text)
    assert_equal [ [ "殺人事件", [ "サツジンジケン" ] ], [ "カレー", [ "カレー", "カレーライス" ] ] ],
                 entries.map { |entry| [ entry.surface, entry.readings ] }

    # 見出しの数が合わない(書式が変わった)・語数の行が無い(確認画面の HTML など)
    assert_nil ResearchCorpus.parse(text.sub("全 2 語", "全 3 語"))
    assert_nil ResearchCorpus.parse("<html>Just a moment...</html>")

    # ファイルが無ければ nil
    assert_nil ResearchCorpus.load(Rails.root.join("tmp/no-such-llms-full.txt"))
  end
end
