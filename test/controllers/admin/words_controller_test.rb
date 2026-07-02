require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::WordsControllerTest < ActionDispatch::IntegrationTest
  setup { @word = words(:abc_murder) }

  # --- 認可: 未認証は弾く ---
  test "未認証だと一覧はログインへリダイレクト" do
    get admin_words_path
    assert_redirected_to new_session_path
  end

  test "未認証だと登録できずログインへリダイレクト" do
    assert_no_difference -> { Word.count } do
      post admin_words_path, params: { word: { surface: "新語" } }
    end
    assert_redirected_to new_session_path
  end

  test "未認証だと削除できない" do
    assert_no_difference -> { Word.count } do
      delete admin_word_path(@word)
    end
    assert_redirected_to new_session_path
  end

  # --- 認証済みの正常系 ---
  test "一覧を表示できる" do
    sign_in_as(Admin.take)
    get admin_words_path
    assert_response :success
    assert_select "td", text: @word.surface
  end

  test "新規フォームを表示できる" do
    sign_in_as(Admin.take)
    get new_admin_word_path
    assert_response :success
  end

  test "語義・特徴つきで単語を登録できる" do
    sign_in_as(Admin.take)

    assert_difference [ "Word.count", "WordSense.count", "WordSenseFeature.count" ], 1 do
      post admin_words_path, params: {
        word: {
          surface: "硫黄島からの手紙",
          word_senses_attributes: {
            "0" => {
              reading: "イオウジマカラノテガミ",
              genre_id: genres(:small_novel).id,
              entity_type_id: entity_types(:book_title).id,
              part_of_speech_id: parts_of_speech(:noun).id,
              meaning: "映画のタイトル",
              word_sense_features_attributes: {
                "0" => { linguistic_feature_id: linguistic_features(:rendaku).id,
                         target: "手紙", target_reading: "テガミ" }
              }
            }
          }
        }
      }
    end

    assert_redirected_to admin_words_path
    word = Word.find_by(surface: "硫黄島からの手紙")
    assert_equal "漢漢漢あああ漢漢", word.char_type_pattern
    sense = word.word_senses.sole
    assert_equal "ioujimakaranotegami", sense.rhythm_pattern
    assert_equal [ linguistic_features(:rendaku) ], sense.linguistic_features
  end

  test "空の語義行はスキップして登録できる" do
    sign_in_as(Admin.take)

    assert_difference -> { Word.count }, 1 do
      assert_no_difference -> { WordSense.count } do
        post admin_words_path, params: {
          word: {
            surface: "空語義テスト",
            word_senses_attributes: { "0" => { reading: "", meaning: "" } }
          }
        }
      end
    end
  end

  test "surface が空だと登録に失敗し 422 を返す" do
    sign_in_as(Admin.take)

    assert_no_difference -> { Word.count } do
      post admin_words_path, params: { word: { surface: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "該当部分が表層形に無いと登録に失敗する" do
    sign_in_as(Admin.take)

    assert_no_difference [ "Word.count", "WordSenseFeature.count" ] do
      post admin_words_path, params: {
        word: {
          surface: "犬",
          word_senses_attributes: {
            "0" => {
              reading: "いぬ",
              word_sense_features_attributes: {
                "0" => { linguistic_feature_id: linguistic_features(:rendaku).id,
                         target: "猫", target_reading: "ねこ" }
              }
            }
          }
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # --- 編集・更新・削除 ---
  test "編集フォームを表示できる" do
    sign_in_as(Admin.take)
    get edit_admin_word_path(@word)
    assert_response :success
  end

  test "surface を更新できる" do
    sign_in_as(Admin.take)
    patch admin_word_path(@word), params: { word: { surface: "更新後の表層" } }
    assert_redirected_to admin_words_path
    assert_equal "更新後の表層", @word.reload.surface
  end

  test "語義を _destroy で削除できる" do
    sign_in_as(Admin.take)
    sense = word_senses(:curry)

    assert_difference -> { WordSense.count }, -1 do
      patch admin_word_path(sense.word), params: {
        word: { word_senses_attributes: { "0" => { id: sense.id, _destroy: "1" } } }
      }
    end
    assert_redirected_to admin_words_path
  end

  test "単語を削除できる(語義・特徴も連鎖削除)" do
    sign_in_as(Admin.take)
    word = word_senses(:murder).word

    assert_difference -> { Word.count }, -1 do
      delete admin_word_path(word)
    end
    assert_redirected_to admin_words_path
    assert_not WordSense.exists?(word_senses(:murder).id)
  end
end
