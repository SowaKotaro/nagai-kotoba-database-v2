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

  # --- 用語解説パネル(Issue 39) ---
  test "特徴欄に用語解説パネルが出る(「音韻添加ってなに?」への答え)" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word)
    assert_select ".ann-features details.ann-glossary" do
      assert_select "summary.ann-glossary__summary", text: /用語解説/
      assert_select ".ann-glossary__item dt", text: "音韻添加"
      assert_select ".ann-glossary__item dd", text: /まんなか/
    end
  end

  # --- 立項スコア(Issue 39) ---
  test "提案パネルに立項スコアが出て、3以下は朱バッジと理由が出る" do
    sign_in_as(Admin.take)
    # フィクスチャは entry_score 5(懸念なし)
    get admin_annotation_path(@word)
    assert_select ".ann-proposal__entry", text: "立項 5/5"
    assert_select ".ann-proposal__entry--concern", count: 0

    proposal = annotation_proposals(:haruhi_proposal)
    proposal.update!(payload: proposal.payload.merge(
      "entry_score" => 2, "entry_notes" => "公然性を欠く。第三者が確認できる媒体に存在しない。"
    ))
    get admin_annotation_path(@word)
    assert_select ".ann-proposal__entry--concern", text: "立項 2/5"
    assert_select ".ann-proposal__notes--entry", text: /公然性を欠く/
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

  test "反映時に小分類が未登録でも大・中まで一致すればピッカーをそこまで開く" do
    sign_in_as(Admin.take)
    # 小分類だけ既存の木に無い提案(大「文学」・中「日本文学」は在る)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "genre_path" => %w[文学 日本文学 私小説]
    })
    get admin_annotation_path(@word, apply_proposal: 1)
    assert_response :success

    # genre_id は未確定のまま(小分類が無いので入れない)
    assert_select "input.js-genre-value[value=?]", genres(:small_novel).id.to_s, count: 0
    # 大・中の id を preselect としてピッカーへ渡す(JS が connect でそこまで潜る)
    expected = [ genres(:large_literature).id, genres(:medium_japanese).id ].to_json
    assert_select ".ann-genre[data-genre-picker-preselect-value=?]", expected
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

  # --- 複数語義の提案(同音異義語・Issue 41) ---
  test "複数語義の提案を反映するとフォームに語義が並ぶ" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [
        { "meaning" => "谷川流のライトノベル。" },
        { "meaning" => "同名のアニメ作品。", "reading" => @sense.reading }
      ]
    })
    get admin_annotation_path(@word, apply_proposal: 1)
    assert_response :success
    assert_select ".ann-sense", count: 2
    assert_select "textarea.js-meaning", text: /谷川流/
    assert_select "textarea.js-meaning", text: /アニメ作品/
  end

  test "複数語義の提案はパネルで語義ごとに区切って表示される" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "meaning" => "語義A。" }, { "meaning" => "語義B。" } ]
    })
    get admin_annotation_path(@word)
    assert_select ".ann-proposal__sense", count: 2
  end

  # --- 注釈済みの語でも提案を見直せる(Issue 41 FB) ---
  test "注釈済みの語でも Claude の提案が状態バッジ付きで表示される" do
    sign_in_as(Admin.take)
    @word.update!(annotated_at: Time.current)
    annotation_proposals(:haruhi_proposal).applied!
    get admin_annotation_path(@word)
    assert_response :success
    assert_select ".ann-proposal"
    assert_select ".ann-proposal__status--applied", text: "反映済み"
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

  test "?proposed=1 で語の詳細を表示できる(キューの id 曖昧を回避)" do
    sign_in_as(Admin.take)
    # show は set_navigation で annotation_proposals を joins したキューを辿る。
    # 素の id だと words.id と annotation_proposals.id で曖昧になり
    # StatementInvalid になっていた(回帰防止)。
    get admin_annotation_path(@word, proposed: 1)
    assert_response :success
  end

  # --- 表層形の訂正(Issue 36: 編集画面をコンソールへ統合) ---
  test "コンソールに表層形の編集欄が出る" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word)
    # 長い表層形も全文表示するため textarea。値は要素の中身に入る(value 属性ではない)。
    assert_select "textarea.ann-surface__input[name=?]", "word[surface]", text: @word.surface
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
