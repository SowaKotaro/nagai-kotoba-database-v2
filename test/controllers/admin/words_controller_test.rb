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

  test "新規フォーム(一括登録)を表示できる" do
    sign_in_as(Admin.take)
    get new_admin_word_path
    assert_response :success
    assert_select "textarea.bulk-input"
  end

  test "表層形と読みをまとめて登録できる(未注釈のまま)" do
    sign_in_as(Admin.take)

    assert_difference [ "Word.count", "WordSense.count" ], 2 do
      post admin_words_path, params: {
        bulk_word_registration: { text: "銀河鉄道の夜　ギンガテツドウノヨル\n活版印刷術　カッパンインサツジュツ" }
      }
    end

    assert_redirected_to admin_words_path
    word = Word.find_by(surface: "銀河鉄道の夜")
    assert_equal "ギンガテツドウノヨル", word.word_senses.sole.reading
    assert_nil word.annotated_at
  end

  test "表層形に半角空白を含む語も登録できる(行末の空白で読みと分ける)" do
    sign_in_as(Admin.take)

    assert_difference -> { Word.count }, 1 do
      post admin_words_path, params: {
        bulk_word_registration: { text: "Dead by Daylight　デッドバイデイライト" }
      }
    end
    assert Word.exists?(surface: "Dead by Daylight")
  end

  test "既存の(表層形・読み)はスキップする(冪等)" do
    sign_in_as(Admin.take)
    line = "#{words(:abc_murder).surface}　#{word_senses(:murder).reading}"

    assert_no_difference [ "Word.count", "WordSense.count" ] do
      post admin_words_path, params: { bulk_word_registration: { text: line } }
    end
    assert_redirected_to admin_words_path
  end

  test "読み欠落の行はエラーにして 422 を返す" do
    sign_in_as(Admin.take)

    assert_no_difference -> { Word.count } do
      post admin_words_path, params: { bulk_word_registration: { text: "読みなし語" } }
    end
    assert_response :unprocessable_entity
    assert_select ".bulk-result__errors li"
  end

  test "テキストが空だと 422 を返す" do
    sign_in_as(Admin.take)

    assert_no_difference -> { Word.count } do
      post admin_words_path, params: { bulk_word_registration: { text: "" } }
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
