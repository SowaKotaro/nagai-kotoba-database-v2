require "test_helper"

# 1語の再調査用データの書き出し。アノテーション・コンソールから /reannotation へ渡す JSON。
class ReannotationExportTest < ActiveSupport::TestCase
  test "注釈済みの語は保存済みの内容を提案 JSON と同じキーで書き出す" do
    word = words(:abc_murder)
    data = ReannotationExport.new(word).as_json

    assert_equal "1", data["version"]
    assert_equal "reannotation", data["format"]
    assert_equal word.id, data["word_id"]
    assert_equal "ABC殺人事件", data["surface"]
    assert_equal "さつじんじけん", data["reading"]

    assert_equal "saved", data["current"]["source"]
    sense = data["current"]["senses"].first
    assert_equal "人を殺す事件", sense["meaning"]
    assert_equal %w[文学 日本文学 小説], sense["genre_path"]
    assert_equal "書籍名", sense["entity_type"]
    assert_equal "名詞", sense["part_of_speech"]
    assert_equal [ "漢語" ], sense["word_origins"]
    assert_equal({ "name" => "連濁", "target" => "殺人", "target_reading" => "さつじん", "target_start" => 3 },
                 sense["linguistic_features"].first)
  end

  test "別表記は surface と reading で書き出し、空の項目はキーごと落とす" do
    sense = ReannotationExport.new(words(:curry)).as_json["current"]["senses"].first

    assert_equal [ { "surface" => "カリー", "reading" => "カリー" } ], sense["variants"]
    # カレーライスの語義には意味・ジャンル・エンティティ・特徴が付いていない。
    assert_not sense.key?("meaning")
    assert_not sense.key?("genre_path")
    assert_not sense.key?("entity_type")
    assert_not sense.key?("linguistic_features")
  end

  test "まだ何も注釈が付いていない語は、取り込み済みの提案を現在値として渡す" do
    word = words(:pending_haruhi)
    data = ReannotationExport.new(word, annotation_proposals(:haruhi_proposal)).as_json

    assert_equal "proposal", data["current"]["source"]
    assert_equal 5, data["current"]["entry_score"]
    assert_equal "high", data["current"]["confidence"]
    # トップレベル形式(単一語義の後方互換)の提案も senses 配列へ畳んで渡す。
    sense = data["current"]["senses"].first
    assert_equal "書籍名", sense["entity_type"]
    assert_equal %w[文学 日本文学 小説], sense["genre_path"]
    assert_equal [ { "surface" => "ハルヒ" } ], sense["variants"]
  end

  test "注釈も提案も無い語は source=none で現在値が空になる" do
    data = ReannotationExport.new(words(:pending_bermuda)).as_json

    assert_equal "none", data["current"]["source"]
    assert_equal [ { "reading" => "バミューダトライアングル" } ], data["current"]["senses"]
  end

  test "注釈済みの語でも、残っている提案のメタ(立項スコア・確信度)は手がかりとして渡す" do
    word = words(:pending_haruhi)
    word.word_senses.first.update!(meaning: "谷川流のライトノベル。")
    data = ReannotationExport.new(word.reload, annotation_proposals(:haruhi_proposal)).as_json

    assert_equal "saved", data["current"]["source"]
    assert_equal 5, data["current"]["entry_score"]
    assert_equal "谷川流のライトノベル。", data["current"]["senses"].first["meaning"]
  end

  test "マスタ一覧は書き出し(AnnotationResearchExport)と同じ形で同梱する" do
    masters = ReannotationExport.new(words(:abc_murder)).as_json["masters"]

    assert_equal AnnotationMasters.as_json, masters
    assert_includes masters["genres"].fetch("文学").fetch("日本文学"), "小説"
  end

  test "to_json は整形済みの JSON 文字列を返す" do
    json = ReannotationExport.new(words(:abc_murder)).to_json

    assert_equal "reannotation", JSON.parse(json)["format"]
    assert_includes json, "\n"
  end
end
