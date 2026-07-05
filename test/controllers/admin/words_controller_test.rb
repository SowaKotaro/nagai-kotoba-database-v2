require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# 一括登録は3ステップ(入力→読み→重複→登録)。読みの自動取得(ReadingExtractor)は
# CI に mecab が無くても安定させるためスタブする。
class Admin::WordsControllerTest < ActionDispatch::IntegrationTest
  setup { @word = words(:abc_murder) }

  # 表層形→読みの対応表を返すスタブ。未知の語は読み空(nil)にする。
  def stub_readings(map)
    callable = ->(surfaces) { surfaces.map { |surface| map[surface] } }
    stub_method(ReadingExtractor, :call, callable) { yield }
  end

  # --- 認可: 未認証は弾く ---
  test "未認証だと一覧はログインへリダイレクト" do
    get admin_words_path
    assert_redirected_to new_session_path
  end

  test "未認証だと読み取得(step2)できずログインへリダイレクト" do
    post readings_admin_words_path, params: { bulk_word_registration: { text: "新語" } }
    assert_redirected_to new_session_path
  end

  test "未認証だと重複チェック(step3)できずログインへリダイレクト" do
    post duplicates_admin_words_path, params: {
      bulk_word_registration: { entries: [ { surface: "新語", reading: "シンゴ" } ] }
    }
    assert_redirected_to new_session_path
  end

  test "未認証だと登録できずログインへリダイレクト" do
    assert_no_difference -> { Word.count } do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [ { surface: "新語", reading: "シンゴ" } ] }
      }
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

  test "新規フォーム(箇条書き貼り付け)を表示できる" do
    sign_in_as(Admin.take)
    get new_admin_word_path
    assert_response :success
    assert_select "textarea.bulk-input"
  end

  # --- step2: 読みの取得 ---
  test "箇条書きから読みを取得すると編集可能な読み欄が出る(重複判定はしない)" do
    sign_in_as(Admin.take)
    readings = { "天上天下唯我独尊" => "テンジョウテンゲユイガドクソン" }

    stub_readings(readings) do
      post readings_admin_words_path, params: {
        bulk_word_registration: { text: "1. 天上天下唯我独尊" }
      }
    end

    assert_response :success
    assert_select "ol.steps li.is-current .steps__label", text: "読み"
    assert_select "input.bulk-review__reading-input[value=?]", "テンジョウテンゲユイガドクソン"
    # bullet(1.)は表層形から取り除かれている
    assert_select "input[name=?][value=?]", "bulk_word_registration[entries][][surface]", "天上天下唯我独尊"
    # step2 では重複警告は出さない
    assert_select "tr.bulk-review__row--warn", false
  end

  test "テキストが空だと読み取得は 422 を返す" do
    sign_in_as(Admin.take)
    post readings_admin_words_path, params: { bulk_word_registration: { text: "" } }
    assert_response :unprocessable_entity
    assert_select "p.form-alert"
  end

  # --- step2: 調査 JSON の反映 ---
  test "調査 JSON を反映すると不一致行に候補チップと不一致バッジが出る" do
    sign_in_as(Admin.take)
    json = {
      version: "1",
      words: [ { input: "花は桜木人は武士", surface: "花は桜木人は武士",
                 reading: "ハナハサクラギヒトハブシ", confidence: "high" } ]
    }.to_json

    post apply_research_admin_words_path, params: {
      bulk_word_registration: {
        entries: [ { surface: "花は桜木人は武士", reading: "ハナハサクラギジンハブシ" } ],
        research_json: json
      }
    }

    assert_response :success
    assert_select ".reading-status--differ"
    assert_select ".reading-choice[data-reading=?]", "ハナハサクラギヒトハブシ"
    # 不一致は既定で調査側(ヒト)を採用する
    assert_select "input.bulk-review__reading-input[value=?]", "ハナハサクラギヒトハブシ"
  end

  test "壊れた調査 JSON は警告を出し MeCab の読みを保つ" do
    sign_in_as(Admin.take)
    post apply_research_admin_words_path, params: {
      bulk_word_registration: {
        entries: [ { surface: "猫", reading: "ネコ" } ],
        research_json: "{ 壊れた"
      }
    }

    assert_response :success
    assert_select "p.form-alert"
    assert_select "input.bulk-review__reading-input[value=?]", "ネコ"
  end

  test "未認証だと調査反映できずログインへリダイレクト" do
    post apply_research_admin_words_path, params: {
      bulk_word_registration: { entries: [ { surface: "猫", reading: "ネコ" } ], research_json: "{}" }
    }
    assert_redirected_to new_session_path
  end

  # step2 フォームは formaction で duplicates と apply_research の2つに送るため、グローバル CSRF
  # トークンを埋める(per-form トークンだと apply_research 側で弾かれる)。CSRF を実際に有効化して確認。
  test "readings フォームのトークンで formaction 先(apply_research)も CSRF を通る" do
    sign_in_as(Admin.take)
    ActionController::Base.allow_forgery_protection = true

    # step1 → step2(readings) を描画(ヘッダのログアウト等と混ざらないよう action で特定)
    get new_admin_word_path
    step1_form = css_select("form").find { |f| f["action"]&.include?("readings") }
    step1_token = step1_form.css("input[name=authenticity_token]").first["value"]
    stub_readings("資本主義" => "シホンシュギ") do
      post readings_admin_words_path, params: {
        authenticity_token: step1_token, bulk_word_registration: { text: "1. 資本主義" }
      }
    end
    assert_response :success

    # readings フォーム(action=duplicates)のトークンを取り出し、formaction 先へ送る
    form = css_select("form").find { |f| f["action"]&.include?("duplicates") }
    token = form.css("input[name=authenticity_token]").first["value"]
    post apply_research_admin_words_path, params: {
      authenticity_token: token,
      bulk_word_registration: {
        entries: [ { surface: "資本主義", reading: "シホンシュギ" } ], research_json: "{}"
      }
    }
    assert_response :success
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  # --- step3: 重複チェック(確定した読みに対して) ---
  test "確定した読みで DB の既存読みに似た語に警告を出す" do
    sign_in_as(Admin.take)
    # murder フィクスチャの読み「さつじんじけん」に一致する読みを渡す
    post duplicates_admin_words_path, params: {
      bulk_word_registration: { entries: [ { surface: "殺人事件", reading: "さつじんじけん" } ] }
    }

    assert_response :success
    assert_select "ol.steps li.is-current .steps__label", text: "重複"
    assert_select "tr.bulk-review__row--warn"
    assert_select ".bulk-review__match-reading", text: "さつじんじけん"
  end

  test "重複チェック画面に除外チェックボックスが表示される" do
    sign_in_as(Admin.take)
    post duplicates_admin_words_path, params: {
      bulk_word_registration: { entries: [ { surface: "資本主義", reading: "シホンシュギ" } ] }
    }
    assert_response :success
    assert_select "input.bulk-review__exclude[type=checkbox]"
  end

  # --- 登録(create) ---
  test "確認後のエントリをまとめて登録できる(未注釈のまま)" do
    sign_in_as(Admin.take)

    assert_difference [ "Word.count", "WordSense.count" ], 2 do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [
          { surface: "銀河鉄道の夜", reading: "ギンガテツドウノヨル" },
          { surface: "活版印刷術", reading: "カッパンインサツジュツ" }
        ] }
      }
    end

    assert_redirected_to admin_words_path
    word = Word.find_by(surface: "銀河鉄道の夜")
    assert_equal "ギンガテツドウノヨル", word.word_senses.sole.reading
    assert_nil word.annotated_at
  end

  test "既存の(表層形・読み)はスキップする(冪等)" do
    sign_in_as(Admin.take)

    assert_no_difference [ "Word.count", "WordSense.count" ] do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [
          { surface: words(:abc_murder).surface, reading: word_senses(:murder).reading }
        ] }
      }
    end
    assert_redirected_to admin_words_path
  end

  test "読み欠落のエントリはエラーにして 422 を返す" do
    sign_in_as(Admin.take)

    assert_no_difference -> { Word.count } do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [ { surface: "読みなし語", reading: "" } ] }
      }
    end
    assert_response :unprocessable_entity
    assert_select ".bulk-result__errors li"
  end

  test "除外(_exclude)にチェックした行は登録されない" do
    sign_in_as(Admin.take)

    assert_difference [ "Word.count", "WordSense.count" ], 1 do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [
          { surface: "登録語", reading: "トウロクゴ" },
          { surface: "除外語", reading: "ジョガイゴ", _exclude: "1" }
        ] }
      }
    end

    assert_redirected_to admin_words_path
    assert Word.exists?(surface: "登録語")
    assert_not Word.exists?(surface: "除外語")
  end

  test "エントリが無いと貼り付け画面へ戻す" do
    sign_in_as(Admin.take)

    assert_no_difference -> { Word.count } do
      post admin_words_path, params: { bulk_word_registration: { entries: [] } }
    end
    assert_redirected_to new_admin_word_path
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
