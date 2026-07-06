require "test_helper"

# 公開 JSON API(Issue 25)の結合テスト。読み取り専用・注釈済みのみ。
class WordsApiTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "単語詳細 .json が語義の全属性とライセンスを返す" do
    word = words(:abc_murder)
    get word_path(word, format: :json)
    assert_response :success
    assert_equal "application/json", response.media_type

    body = JSON.parse(response.body)
    assert_equal word.id, body["id"]
    assert_equal word.surface, body["surface"]
    assert_equal "#{HOST}/words/#{word.id}", body["url"]

    sense = body["senses"].first
    assert_equal word_senses(:murder).reading, sense["reading"]
    assert_equal word_senses(:murder).meaning, sense["meaning"]
    assert_equal 7, sense["reading_length"]
    assert_equal [ "文学", "日本文学", "小説" ], sense["genre"].map { |g| g["name"] }
    assert_equal "名詞", sense["part_of_speech"]
    assert_includes sense["word_origins"], "漢語"
    assert_equal "連濁", sense["linguistic_features"].first["name"]

    assert_equal "CC BY 4.0", body["license"]["name"]
    assert_includes body["license"]["credit"], HOST
  end

  test "未注釈の語の .json は 404" do
    get word_path(words(:pending_haruhi), format: :json)
    assert_response :not_found
  end

  test "単語一覧 .json がページ情報つきで返る" do
    get words_path(format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["page"]
    assert body["total_count"].positive?
    surfaces = body["words"].map { |w| w["surface"] }
    assert_includes surfaces, words(:abc_murder).surface
    assert_not_includes surfaces, words(:pending_haruhi).surface
    assert_equal "CC BY 4.0", body["license"]["name"]
  end

  test "一覧 .json はファセット絞り込みを反映する" do
    get words_path(format: :json, first_char: word_senses(:curry).first_char)
    body = JSON.parse(response.body)
    surfaces = body["words"].map { |w| w["surface"] }
    assert_includes surfaces, words(:curry).surface
    assert_not_includes surfaces, words(:abc_murder).surface
  end
end
