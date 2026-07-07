require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::AnnotationsControllerTest < ActionDispatch::IntegrationTest
  # コンソールは未注釈語(annotated_at なし)を対象にする。
  setup do
    @word = words(:pending_haruhi)
    @sense = word_senses(:pending)
  end

  # --- 認可: 未認証は弾く ---
  test "未認証だとコンソールはログインへリダイレクト" do
    get admin_annotation_path(@word)
    assert_redirected_to new_session_path
  end

  test "未認証だと保存できない" do
    patch admin_annotation_path(@word), params: { word: { word_senses_attributes: { "0" => { id: @sense.id, reading: @sense.reading } } } }
    assert_redirected_to new_session_path
    assert_nil @word.reload.annotated_at
  end

  test "未認証だとマスタをその場追加できない" do
    assert_no_difference -> { WordOrigin.count } do
      post admin_word_origins_path, params: { name: "タミル語" }, as: :json
    end
  end

  # --- index: 最初の未注釈へ誘導 ---
  test "index は最初の未注釈へリダイレクトする" do
    sign_in_as(Admin.take)
    get admin_annotations_path
    assert_response :redirect
    assert_match %r{/admin/annotations/\d+}, @response.redirect_url
  end

  # --- show: コンソールを描画できる(全 partial のスモーク) ---
  test "コンソールを描画できる" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word)
    assert_response :success
    assert_select "h1.ann-word", text: @word.surface
    assert_select ".ann-chip"          # 語種・品詞などのチップ
    assert_select ".ann-strip"         # 特徴の文字ストリップ枠
  end

  # --- update: 語種(多対多)・ジャンル・意味を保存し annotated_at をセット ---
  test "注釈を保存すると annotated_at がセットされ次の未注釈へ進む" do
    sign_in_as(Admin.take)
    patch admin_annotation_path(@word), params: {
      word: { word_senses_attributes: { "0" => {
        id: @sense.id, reading: @sense.reading, meaning: "更新後の意味",
        genre_id: genres(:small_novel).id, part_of_speech_id: parts_of_speech(:noun).id,
        word_origin_ids: [ word_origins(:wago).id, word_origins(:kango).id ]
      } } }
    }
    @word.reload
    assert_not_nil @word.annotated_at
    assert_equal "更新後の意味", @sense.reload.meaning
    assert_equal [ word_origins(:kango).id, word_origins(:wago).id ].sort, @sense.word_origin_ids.sort
    # 残る未注釈(pending_bermuda)へ誘導する。
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))
  end

  # --- Claude の提案(Issue 38) ---
  test "提案のある語には提案パネルが出る" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word)
    assert_select ".ann-proposal" do
      assert_select ".ann-proposal__grid dd", text: /谷川流/
      assert_select "a", text: "提案を反映"
    end
    # 提案の無い語には出ない
    get admin_annotation_path(words(:pending_bermuda))
    assert_select ".ann-proposal", count: 0
  end

  test "「提案を反映」でフォームに提案値がプレフィルされる(保存はしない)" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word, apply_proposal: 1)
    assert_response :success

    # 意味・ジャンル(解決済み)・エンティティ・品詞・語種・別表記
    assert_select "textarea.js-meaning", text: /谷川流/
    assert_select "input.js-genre-value[value=?]", genres(:small_novel).id.to_s
    assert_select "input[type=radio][value=?][checked]", entity_types(:book_title).id.to_s
    assert_select "input[type=radio][value=?][checked]", parts_of_speech(:noun).id.to_s
    assert_select "input[type=checkbox][value=?][checked]", word_origins(:wago).id.to_s
    assert_select "input[value=?]", "ハルヒ"

    # プレフィルは表示だけで、DB には書き込まない
    @sense.reload
    assert_nil @sense.meaning
    assert_nil @sense.genre_id
    assert_empty @sense.word_origin_ids
  end

  test "保存(承認)すると提案が applied になる" do
    sign_in_as(Admin.take)
    proposal = annotation_proposals(:haruhi_proposal)

    patch admin_annotation_path(@word), params: {
      word: { word_senses_attributes: { "0" => {
        id: @sense.id, reading: @sense.reading, meaning: "確認済みの意味。"
      } } }
    }

    assert proposal.reload.applied?
    assert_not_nil @word.reload.annotated_at
  end

  test "?proposed=1 のキューは未承認の提案がある語だけを辿る" do
    sign_in_as(Admin.take)
    # 提案があるのは haruhi だけなので、index はそこへ誘導する
    get admin_annotations_path(proposed: 1)
    assert_redirected_to admin_annotation_path(@word, proposed: 1)

    # 保存後、提案のある語が尽きたら完了(index)へ。フィルタは保たれる
    patch admin_annotation_path(@word), params: {
      proposed: "1",
      word: { word_senses_attributes: { "0" => { id: @sense.id, reading: @sense.reading } } }
    }
    assert_redirected_to admin_annotations_path(proposed: 1)
  end

  # --- 表層形の訂正(Issue 36: 編集画面をコンソールへ統合) ---
  test "コンソールに表層形の編集欄が出る" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word)
    assert_select "input.ann-surface__input[name=?][value=?]", "word[surface]", @word.surface
  end

  test "表層形を訂正すると char_type_pattern が再生成される" do
    sign_in_as(Admin.take)
    patch admin_annotation_path(@word), params: {
      word: { surface: "すずみやハルヒの憂鬱",
              word_senses_attributes: { "0" => { id: @sense.id, reading: @sense.reading } } }
    }
    @word.reload
    assert_equal "すずみやハルヒの憂鬱", @word.surface
    assert_equal "ああああアアアあ漢漢", @word.char_type_pattern
  end

  test "別表記と特徴をネストして保存できる" do
    sign_in_as(Admin.take)
    assert_difference -> { WordSenseVariant.count } => 1 do
      patch admin_annotation_path(@word), params: {
        word: { word_senses_attributes: { "0" => {
          id: @sense.id, reading: @sense.reading,
          word_sense_variants_attributes: { "0" => { surface: "殺人事件（別表記）", reading: "さつじんじけん" } }
        } } }
      }
    end
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))
  end

  # --- スティッキー引き継ぎ(Issue 37) ---
  test "トグルONで保存すると、次の語にジャンル・品詞・語種が初期値として入る" do
    sign_in_as(Admin.take)
    patch admin_annotation_path(@word), params: {
      sticky: "1",
      word: { word_senses_attributes: { "0" => {
        id: @sense.id, reading: @sense.reading,
        genre_id: genres(:small_novel).id, part_of_speech_id: parts_of_speech(:noun).id,
        word_origin_ids: [ word_origins(:wago).id ]
      } } }
    }
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))

    get admin_annotation_path(words(:pending_bermuda))
    assert_select "input.js-genre-value[value=?]", genres(:small_novel).id.to_s
    assert_select "input[type=radio][value=?][checked]", parts_of_speech(:noun).id.to_s
    assert_select "input[type=checkbox][value=?][checked]", word_origins(:wago).id.to_s
    # 引き継ぎはフォームの初期値のみで、DB には書き込まない
    assert_nil word_senses(:pending2).reload.genre_id
    assert_empty word_senses(:pending2).word_origin_ids
  end

  test "トグルOFF(既定)なら引き継がない" do
    sign_in_as(Admin.take)
    patch admin_annotation_path(@word), params: {
      word: { word_senses_attributes: { "0" => {
        id: @sense.id, reading: @sense.reading, genre_id: genres(:small_novel).id
      } } }
    }

    get admin_annotation_path(words(:pending_bermuda))
    assert_select "input.js-genre-value[value=?]", genres(:small_novel).id.to_s, count: 0
  end

  test "属性が既に付いている語義には引き継ぎで上書きしない" do
    sign_in_as(Admin.take)
    patch admin_annotation_path(@word), params: {
      sticky: "1",
      word: { word_senses_attributes: { "0" => {
        id: @sense.id, reading: @sense.reading, genre_id: genres(:small_novel).id
      } } }
    }

    # abc_murder は品詞・ジャンル等が設定済みなので、そのまま表示される
    get admin_annotation_path(words(:abc_murder))
    murder_sense = word_senses(:murder)
    assert_select "input.js-genre-value[value=?]", murder_sense.genre_id.to_s
  end

  # --- マスタのその場追加 ---
  test "語種をその場で追加できる(JSON)" do
    sign_in_as(Admin.take)
    assert_difference -> { WordOrigin.count } => 1 do
      post admin_word_origins_path, params: { name: "タミル語" }, as: :json
    end
    assert_response :success
    assert_equal "タミル語", response.parsed_body["name"]
  end

  test "小分類ジャンルをその場で追加できる(親の下に作成)" do
    sign_in_as(Admin.take)
    assert_difference -> { Genre.count } => 1 do
      post admin_genres_path, params: { name: "新しい小分類", parent_id: genres(:medium_japanese).id }, as: :json
    end
    created = Genre.find(response.parsed_body["id"])
    assert created.small?
    assert_equal genres(:medium_japanese), created.parent
  end
end
