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

  # 外部に出す形式なので、キーの集合と入れ子ごと固定する(キーの欠落・改名・並びの変化を検出する)。
  test "単語詳細 .json のキーの集合と入れ子" do
    get word_path(words(:abc_murder), format: :json)
    body = JSON.parse(response.body)

    assert_equal %w[id surface url char_type_pattern senses license], body.keys
    assert_equal words(:abc_murder).char_type_pattern, body["char_type_pattern"]

    sense = body["senses"].first
    assert_equal %w[reading meaning reading_length mora_count first_char last_char rhythm_pattern vowel_pattern
                    genre part_of_speech entity_type word_origins linguistic_features variants], sense.keys
    murder = word_senses(:murder)
    assert_equal [ murder.mora_count, murder.first_char, murder.last_char, murder.rhythm_pattern, murder.vowel_pattern ],
                 sense.values_at("mora_count", "first_char", "last_char", "rhythm_pattern", "vowel_pattern")
    assert_equal [ { "id" => genres(:large_literature).id, "name" => "文学", "level" => "large" },
                   { "id" => genres(:medium_japanese).id, "name" => "日本文学", "level" => "medium" },
                   { "id" => genres(:small_novel).id, "name" => "小説", "level" => "small" } ],
                 sense["genre"]
    assert_equal murder.entity_type.name, sense["entity_type"]
    assert_equal %w[name target target_reading], sense["linguistic_features"].first.keys

    assert_equal({ "name" => "CC BY 4.0", "url" => "https://creativecommons.org/licenses/by/4.0/deed.ja",
                   "credit" => "長い言葉のデータベース (#{HOST})" }, body["license"])
  end

  test "ジャンルの無い語義の genre は null、別表記は surface と reading の配列" do
    get word_path(words(:curry), format: :json)
    sense = JSON.parse(response.body)["senses"].first

    assert sense.key?("genre")
    assert_nil sense["genre"]
    assert_nil sense["entity_type"]
    assert_equal [ { "surface" => "カリー", "reading" => "カリー" } ], sense["variants"]
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

    assert_equal %w[page total_pages total_count words license], body.keys
    assert_equal 1, body["total_pages"]
    word = body["words"].find { |w| w["id"] == words(:abc_murder).id }
    assert_equal %w[id surface url readings], word.keys
    assert_equal "#{HOST}/words/#{words(:abc_murder).id}", word["url"]
    assert_equal [ word_senses(:murder).reading ], word["readings"]
  end

  test "一覧 .json はファセット絞り込みを反映する" do
    get words_path(format: :json, first_char: word_senses(:curry).first_char)
    body = JSON.parse(response.body)
    surfaces = body["words"].map { |w| w["surface"] }
    assert_includes surfaces, words(:curry).surface
    assert_not_includes surfaces, words(:abc_murder).surface
  end
end
