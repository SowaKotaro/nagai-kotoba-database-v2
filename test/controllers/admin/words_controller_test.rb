require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# 単語管理一覧と、一括登録の3ステップ(入力→読み→重複→登録)。解析・重複判定・登録の中身は
# BulkWordRegistrationTest、読み欄のフロント検証は AdminWordsReadingFormatTest で見る。
# 読みの自動取得(ReadingExtractor)は CI に mecab が無くても安定させるためスタブする。
class Admin::WordsControllerTest < ActionDispatch::IntegrationTest
  setup { @word = words(:abc_murder) }

  # 表層形→読みの対応表を返すスタブ。未知の語は読み空(nil)にする。
  def stub_readings(map)
    callable = ->(surfaces) { surfaces.map { |surface| map[surface] } }
    stub_method(ReadingExtractor, :call, callable) { yield }
  end

  # --- 認可: 未認証は弾く ---

  # --- 一覧 ---
  test "一覧に読み・注釈状態・件数とコンソールへのリンクが出る" do
    sign_in_as(Admin.take)
    get admin_words_path
    assert_response :success
    # 表層形はコンソール(ピンポイント・アノテーション)へのリンク
    assert_select "td a[href=?]", admin_annotation_path(@word), text: @word.surface
    # 読み・注釈状態(注釈済みは日付、未注釈はラベル)
    assert_select "td.admin-words-table__reading", text: /さつじんじけん/
    assert_select ".admin-words-table__annotated", text: @word.annotated_at.strftime("%Y-%m-%d")
    assert_select ".admin-words-table__unannotated", text: "未対応", minimum: 1
    # 件数表示とページネーション
    assert_select ".admin-words-count", text: /#{Word.count}\s*語/
    assert_select ".pagination span", text: "1 / 1 ページ"
  end

  test "一覧に一括適用パネルと選択チェックボックスが出る(Issue 37)" do
    sign_in_as(Admin.take)
    get admin_words_path
    # パネル(ジャンルピッカー・チップ・テンプレ文・注釈済みチェック)
    assert_select ".bulk-annotation form#bulk-annotation-form" do
      assert_select "input.js-genre-value"
      assert_select "input[name=?]", "bulk_annotation[entity_type_id]"
      assert_select "input[name=?]", "bulk_annotation[meaning_template]"
      # 注釈済みフラグは既定 OFF
      assert_select "input[name=?][checked]", "bulk_annotation[mark_annotated]", count: 0
    end
    # 行のチェックボックスは form 属性で外のフォームに紐づく
    assert_select "tbody input[type=checkbox][name=?][form=bulk-annotation-form][value=?]",
                  "bulk_annotation[word_ids][]", @word.id.to_s
  end

  test "一覧を表層形・読み・別表記で検索できる" do
    sign_in_as(Admin.take)
    # 表層形の部分一致
    get admin_words_path(q: "ハルヒ")
    assert_select "td a", text: words(:pending_haruhi).surface
    assert_select "td a", text: @word.surface, count: 0
    # 読みの部分一致
    get admin_words_path(q: "さつじん")
    assert_select "td a", text: @word.surface
    # 別表記の部分一致(公開検索と条件を共有する。Issue 72)
    get admin_words_path(q: word_sense_variants(:curry_variant).surface)
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: @word.surface, count: 0
  end

  test "一覧を注釈状態(未対応/保留/完了)で絞り込める" do
    sign_in_as(Admin.take)
    # 未対応: 保留・完了の語は出さない
    get admin_words_path(status: "annotation_pending")
    assert_select "td a", text: words(:pending_haruhi).surface
    assert_select "td a", text: @word.surface, count: 0
    assert_select "td a", text: words(:on_hold_word).surface, count: 0
    assert_select ".admin-status-tabs__tab[aria-current=page]", text: "未対応"

    # 保留: 保留の語だけ出す
    get admin_words_path(status: "annotation_on_hold")
    assert_select "td a", text: words(:on_hold_word).surface
    assert_select "td a", text: words(:pending_haruhi).surface, count: 0
    assert_select "td a", text: @word.surface, count: 0

    # 完了: 注釈済みの語だけ出す
    get admin_words_path(status: "annotation_done")
    assert_select "td a", text: @word.surface
    assert_select "td a", text: words(:pending_haruhi).surface, count: 0
  end

  test "一覧をタグ(品詞・エンティティ・語種・ジャンル)で絞り込め、ジャンルは大分類でも配下ごと絞る" do
    sign_in_as(Admin.take)
    # 品詞「名詞」: murder と curry の語義に付いている
    get admin_words_path(part_of_speech_id: parts_of_speech(:noun).id)
    assert_select "td a", text: @word.surface
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: words(:pending_haruhi).surface, count: 0

    # エンティティ「書籍名」: murder のみ
    get admin_words_path(entity_type_id: entity_types(:book_title).id)
    assert_select "td a", text: @word.surface
    assert_select "td a", text: words(:curry).surface, count: 0

    # 語種「英語」: curry のみ
    get admin_words_path(word_origin_id: word_origins(:eigo).id)
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: @word.surface, count: 0

    # ジャンルは小分類を直接指定しても、大分類を選んでも配下の小説に付く語が出る
    [ genres(:small_novel), genres(:large_literature) ].each do |genre|
      get admin_words_path(genre_id: genre.id)
      assert_select "td a", text: @word.surface
      assert_select "td a", text: words(:curry).surface, count: 0
    end

    # 存在しないジャンル id は0件(絞り込みは黙って外さない)
    get admin_words_path(genre_id: 999_999)
    assert_select "p.empty-note"
  end

  test "タグ絞り込みは検索・注釈状態と組み合わせられる(AND)" do
    sign_in_as(Admin.take)
    # 品詞「名詞」× 表層形「カレー」→ curry のみ
    get admin_words_path(part_of_speech_id: parts_of_speech(:noun).id, q: "カレー")
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: @word.surface, count: 0

    # 品詞「名詞」× 未対応 → 0件(名詞が付く語はどちらも注釈済み)
    get admin_words_path(part_of_speech_id: parts_of_speech(:noun).id, status: "annotation_pending")
    assert_select "p.empty-note"
  end

  test "タグ絞り込みは状態タブ・一括適用フォーム・セレクトに引き継がれる" do
    sign_in_as(Admin.take)
    pos_id = parts_of_speech(:noun).id
    get admin_words_path(part_of_speech_id: pos_id)

    # 状態タブのリンクが条件を保持する
    assert_select ".admin-status-tabs__tab[href*=?]", "part_of_speech_id=#{pos_id}", count: 4
    # 一括適用フォームの hidden で適用後も条件を保つ
    assert_select "#bulk-annotation-form input[type=hidden][name=part_of_speech_id][value=?]", pos_id.to_s
    # セレクトは選択状態を復元し、解除リンクが出る
    assert_select "select[name=part_of_speech_id] option[selected][value=?]", pos_id.to_s
    assert_select ".admin-words-tag-filter__reset"
  end

  test "一覧は100語ごとにページ送りする" do
    sign_in_as(Admin.take)
    # コールバックを通さず一括投入(char_type_pattern は NOT NULL のため明示)
    Word.insert_all((1..110).map { |i| { surface: "ページ送り検証語#{format('%03d', i)}", char_type_pattern: "漢" } })

    get admin_words_path
    assert_select "tbody tr", count: 100
    assert_select ".pagination a", text: "次へ"

    get admin_words_path(page: 2)
    assert_select ".pagination a", text: "前へ"
    assert_select ".pagination span", text: "2 / 2 ページ"
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

  test "読みが収録基準(10文字)未満の語はエラー表示し、除外に既定でチェックを入れる" do
    sign_in_as(Admin.take)
    post duplicates_admin_words_path, params: {
      bulk_word_registration: { entries: [
        { surface: "資本主義", reading: "シホンシュギ" },            # 6文字: 収録基準未満
        { surface: "銀河鉄道の夜", reading: "ギンガテツドウノヨル" } # 10文字: 収録できる
      ] }
    }

    assert_response :success
    # 行ごとに除外チェックボックスがあり、基準未満の行だけ既定で除外する
    assert_select "input.bulk-review__exclude[type=checkbox]", count: 2
    assert_select "input.bulk-review__exclude[checked]", count: 1
    assert_select "tr.bulk-review__row--error", count: 1
    assert_select ".bulk-review__error-label", text: /読み 6 文字/
  end

  # --- 登録(create) ---
  test "確認後のエントリを未注釈のまままとめて登録し、除外(_exclude)にチェックした行は登録しない" do
    sign_in_as(Admin.take)

    assert_difference [ "Word.count", "WordSense.count" ], 2 do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [
          { surface: "銀河鉄道の夜", reading: "ギンガテツドウノヨル" },
          { surface: "活版印刷術", reading: "カッパンインサツジュツ" },
          { surface: "除外語", reading: "ジョガイゴ", _exclude: "1" }
        ] }
      }
    end

    assert_redirected_to admin_words_path
    word = Word.find_by(surface: "銀河鉄道の夜")
    assert_equal "ギンガテツドウノヨル", word.word_senses.sole.reading
    assert_nil word.annotated_at
    assert_not Word.exists?(surface: "除外語")
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

  test "エントリが無いと貼り付け画面へ戻す" do
    sign_in_as(Admin.take)

    assert_no_difference -> { Word.count } do
      post admin_words_path, params: { bulk_word_registration: { entries: [] } }
    end
    assert_redirected_to new_admin_word_path
  end

  # --- 削除(編集はコンソールへ統合済み。Issue 36) ---
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
