require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# 高速アノテーション・コンソール(1語集中キュー)。提案 payload の読み方は AnnotationProposalTest、
# 新設候補マスタの作り方は ProposedMasterCreationTest、ブラウザでの挙動は AdminAnnotationConsoleTest で見る。
class Admin::AnnotationsControllerTest < ActionDispatch::IntegrationTest
  # コンソールは未注釈語(annotated_at なし)を対象にする。
  setup do
    @word = words(:pending_haruhi)
    @sense = word_senses(:pending)
  end

  # --- 認可: 未認証は弾く ---
  test "未認証だとコンソールの閲覧・保存・保留・マスタ作成・再調査データはログインへ戻す" do
    get admin_annotation_path(@word)
    assert_redirected_to new_session_path

    get reresearch_admin_annotation_path(@word)
    assert_redirected_to new_session_path

    patch admin_annotation_path(@word), params: { word: { word_senses_attributes: { "0" => { id: @sense.id, reading: @sense.reading } } } }
    assert_redirected_to new_session_path

    patch hold_admin_annotation_path(@word)
    assert_redirected_to new_session_path

    assert_no_difference -> { EntityType.count } do
      post create_master_admin_annotation_path(@word), params: { field: "entity_type" }
    end
    assert_redirected_to new_session_path

    @word.reload
    assert @word.annotation_pending?
    assert_nil @word.annotated_at
  end

  # --- index: 入口は提案付きの語を優先(Issue 69) ---
  test "入口は未承認の提案がある語へ寄せ、提案キューを辿り切ると提案キューの完了画面へ戻る" do
    sign_in_as(Admin.take)
    # フィクスチャでは haruhi に未承認の提案が付いている
    get admin_annotations_path
    assert_redirected_to admin_annotations_path(proposed: 1)
    follow_redirect!
    assert_redirected_to admin_annotation_path(@word, proposed: 1)

    # 提案のある語は haruhi だけなので、保存するとフィルタを保ったまま完了(index)へ
    patch admin_annotation_path(@word), params: {
      proposed: "1",
      word: { word_senses_attributes: { "0" => { id: @sense.id, reading: @sense.reading } } }
    }
    assert_redirected_to admin_annotations_path(proposed: 1)
  end

  test "提案が無ければ入口は最初の未対応へ進む" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).applied!
    get admin_annotations_path
    assert_redirected_to admin_annotation_path(Word.annotation_pending.order(:id).first)
  end

  # --- index: キューを捌き切ったときの完了画面の出し分け(Issue 69) ---
  test "提案キューを捌き切ると残りの未対応語数と書き出しへの導線を出す" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).applied!
    get admin_annotations_path(proposed: 1)
    assert_response :success
    assert_select ".ann-done__lead", text: "提案付きの未対応語はありません"
    assert_select "a[href=?]", export_admin_annotation_proposals_path
    assert_select "a[href=?]", admin_annotations_path, text: "提案なしで進める"
  end

  test "要判断で絞った提案が尽きても他の提案が残っていれば提案キューへの導線を出す" do
    sign_in_as(Admin.take)
    # haruhi の提案は high/立項5 なので「要判断」には掛からず、review キューは空になる
    get admin_annotations_path(proposed: 1, review: 1)
    assert_response :success
    assert_select ".ann-done__lead", text: "要判断の提案は片付きました"
    assert_select "a[href=?]", admin_annotations_path(proposed: 1), text: "残りの提案キューへ(1語)"
  end

  test "未対応の語が無ければ全完了の画面を出す" do
    sign_in_as(Admin.take)
    Word.annotation_pending.find_each do |word|
      word.mark_annotated
      word.save!
    end
    get admin_annotations_path
    assert_response :success
    assert_select ".ann-done__lead", text: "未対応の語はありません"
  end

  # --- show ---
  test "コンソールに表層形の編集欄・チップ・特徴ストリップ・用語解説・再調査への導線が出る" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word)
    assert_response :success
    assert_select "h1.ann-word", text: @word.surface
    # 長い表層形も全文表示するため textarea。値は要素の中身に入る(value 属性ではない)
    assert_select "textarea.ann-surface__input[name=?]", "word[surface]", text: @word.surface
    assert_select ".ann-chip"  # 語種・品詞などのチップ
    assert_select ".ann-strip" # 特徴の文字ストリップ枠
    # 用語解説パネル(Issue 39。「音韻添加ってなに?」への答え)
    assert_select ".ann-features details.ann-glossary" do
      assert_select "summary.ann-glossary__summary", text: /用語解説/
      assert_select ".ann-glossary__item dt", text: "音韻添加"
      assert_select ".ann-glossary__item dd", text: /まんなか/
    end
    assert_select "a[href=?]", reresearch_admin_annotation_path(@word)
  end

  # --- update ---
  test "保存すると語種(多対多)・ジャンル・意味が入って公開され、提案は反映済みになり、次の未対応へ進む" do
    sign_in_as(Admin.take)
    patch admin_annotation_path(@word), params: {
      word: { word_senses_attributes: { "0" => {
        id: @sense.id, reading: @sense.reading, meaning: "更新後の意味",
        genre_id: genres(:small_novel).id, part_of_speech_id: parts_of_speech(:noun).id,
        word_origin_ids: [ word_origins(:wago).id, word_origins(:kango).id ]
      } } }
    }
    # 残る未対応(pending_bermuda)へ誘導する
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))

    @word.reload
    assert_not_nil @word.annotated_at
    assert @word.annotation_done?
    assert annotation_proposals(:haruhi_proposal).reload.applied?
    @sense.reload
    assert_equal "更新後の意味", @sense.meaning
    assert_equal genres(:small_novel).id, @sense.genre_id
    assert_equal [ word_origins(:kango).id, word_origins(:wago).id ].sort, @sense.word_origin_ids.sort
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

  test "別表記と特徴をネストして保存でき、特徴の出現位置(target_start)は先頭の出現に補完される" do
    sign_in_as(Admin.take)
    assert_difference [ "WordSenseVariant.count", "WordSenseFeature.count" ], 1 do
      patch admin_annotation_path(@word), params: {
        word: { word_senses_attributes: { "0" => {
          id: @sense.id, reading: @sense.reading,
          word_sense_variants_attributes: { "0" => { surface: "涼宮ハルヒの憂うつ", reading: "すずみやはるひのゆううつ" } },
          word_sense_features_attributes: { "0" => {
            linguistic_feature_id: linguistic_features(:rendaku).id, target: "涼宮", target_reading: "すずみや"
          } }
        } } }
      }
    end
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))

    feature = @sense.reload.word_sense_features.first
    assert_equal [ "涼宮", "すずみや", 0 ], [ feature.target, feature.target_reading, feature.target_start ]
  end

  # --- hold: 保留にしてキューから外し、次の未対応へ進む ---
  test "保留にすると状態が保留になりキューから外れ、次の未対応へ進む" do
    sign_in_as(Admin.take)
    patch hold_admin_annotation_path(@word)

    @word.reload
    assert @word.annotation_on_hold?
    assert_nil @word.annotated_at
    assert_not_includes Word.annotation_pending, @word
    assert_redirected_to admin_annotation_path(words(:pending_bermuda))
    assert_equal "保留にしました。あとで単語一覧の「保留」から見直せます。", flash[:notice]
  end

  # --- Claude の提案(Issue 38・39) ---
  test "提案のある語にだけ提案パネルが出て、立項スコアが3以下なら懸念の印と理由が出る" do
    sign_in_as(Admin.take)
    # フィクスチャは entry_score 5(懸念なし)
    get admin_annotation_path(@word)
    assert_select ".ann-proposal" do
      assert_select ".ann-proposal__grid dd", text: /谷川流/
      assert_select "a", text: "提案を反映"
    end
    assert_select ".ann-proposal__entry", text: "立項 5/5"
    assert_select ".ann-proposal__entry--concern", count: 0

    proposal = annotation_proposals(:haruhi_proposal)
    proposal.update!(payload: proposal.payload.merge(
      "entry_score" => 2, "entry_notes" => "公然性を欠く。第三者が確認できる媒体に存在しない。"
    ))
    get admin_annotation_path(@word)
    assert_select ".ann-proposal__entry--concern", text: "立項 2/5"
    assert_select ".ann-proposal__notes--entry", text: /公然性を欠く/

    # 提案の無い語には出ない
    get admin_annotation_path(words(:pending_bermuda))
    assert_select ".ann-proposal", count: 0
  end

  test "注釈済みの語でも提案を状態バッジ付きで見直せる" do
    sign_in_as(Admin.take)
    @word.update!(annotated_at: Time.current)
    annotation_proposals(:haruhi_proposal).applied!
    get admin_annotation_path(@word)
    assert_response :success
    assert_select ".ann-proposal"
    assert_select ".ann-proposal__status--applied", text: "反映済み"
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

  # --- 複数語義の提案(同音異義語・Issue 41) ---
  test "複数語義の提案はパネルで語義ごとに区切り、反映するとフォームに語義が並ぶ" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [
        { "meaning" => "谷川流のライトノベル。" },
        { "meaning" => "同名のアニメ作品。", "reading" => @sense.reading }
      ]
    })
    get admin_annotation_path(@word)
    assert_select ".ann-proposal__sense", count: 2

    get admin_annotation_path(@word, apply_proposal: 1)
    assert_response :success
    assert_select ".ann-sense", count: 2
    assert_select "textarea.js-meaning", text: /谷川流/
    assert_select "textarea.js-meaning", text: /アニメ作品/
  end

  # --- 提案の言語的特徴の表示・反映(Issue 63) ---
  test "既存マスタに解決できる特徴は該当部分つきでパネルに出て、反映でフォームに組まれる(保存はしない)" do
    sign_in_as(Admin.take)
    propose_feature("連濁")

    get admin_annotation_path(@word)
    assert_select ".ann-proposal__feature", text: /連濁/
    assert_select ".ann-proposal__feature-target", text: /涼宮/
    assert_select ".ann-proposal__feature .ann-proposal__new", count: 0 # 新設候補ではない

    get admin_annotation_path(@word, apply_proposal: 1)
    assert_response :success
    # 特徴の種別と該当部分が hidden field に入る(feature-range が connect でハイライトを復元する)
    assert_select "input[name$='[linguistic_feature_id]'][value=?]", linguistic_features(:rendaku).id.to_s
    assert_select "input[name$='[target]'][value=?]", "涼宮"
    assert_select "input[name$='[target_reading]'][value=?]", "すずみや"
    assert_equal 0, @sense.reload.word_sense_features.count
  end

  test "未知の特徴名は新設候補の印を付け、反映でもフォームに組まない" do
    sign_in_as(Admin.take)
    propose_feature("存在しない特徴")

    get admin_annotation_path(@word)
    assert_select ".ann-proposal__feature .ann-proposal__new"

    get admin_annotation_path(@word, apply_proposal: 1)
    assert_response :success
    assert_select "input[name$='[target]'][value=?]", "涼宮", count: 0
  end

  # --- 新設候補マスタのワンタップ作成(Issue 66) ---
  test "単一語義の提案では未解決マスタに作成ボタンを出し、複数語義では印だけにする" do
    sign_in_as(Admin.take)
    proposal = annotation_proposals(:haruhi_proposal)
    proposal.update!(payload: { "senses" => [ { "meaning" => "x。", "entity_type" => "架空種別" } ] })
    get admin_annotation_path(@word)
    assert_select "form.ann-proposal__new-form", minimum: 1

    proposal.update!(payload: { "senses" => [ { "entity_type" => "架空種別A" }, { "entity_type" => "架空種別B" } ] })
    get admin_annotation_path(@word)
    assert_select "form.ann-proposal__new-form", count: 0
    assert_select ".ann-proposal__new", minimum: 1
  end

  test "create_master でエンティティを作成し、再反映で解決してフォームに入る" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "meaning" => "x。", "entity_type" => "架空種別" } ]
    })
    assert_difference -> { EntityType.count } => 1 do
      post create_master_admin_annotation_path(@word), params: { field: "entity_type" }
    end
    assert_redirected_to admin_annotation_path(@word, apply_proposal: 1)
    follow_redirect!
    assert_select "input[type=radio][value=?][checked]", EntityType.find_by(name: "架空種別").id.to_s
  end

  test "create_master は候補が複数ある種別(語種)を指定した名前で作る" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "word_origins" => %w[和語 タミル語] } ]
    })
    assert_difference -> { WordOrigin.count } => 1 do
      post create_master_admin_annotation_path(@word), params: { field: "word_origin", name: "タミル語" }
    end
    assert_not_nil WordOrigin.find_by(name: "タミル語")
  end

  test "create_master は作れない指定で alert を出して戻る" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "genre_path" => %w[無い 無い 無い] } ]
    })
    assert_no_difference -> { Genre.count } do
      post create_master_admin_annotation_path(@word), params: { field: "genre" }
    end
    assert_redirected_to admin_annotation_path(@word, apply_proposal: 1)
    assert_equal I18n.t("admin.annotations.create_master_failed"), flash[:alert]
  end

  # --- キューの絞り込み・並べ替え(Issue 67) ---
  test "提案キューにだけ絞り込み・並べ替えの導線が出る" do
    sign_in_as(Admin.take)
    get admin_annotation_path(@word, proposed: 1)
    assert_select ".ann-queue-filter"
    assert_select ".ann-queue-filter__link", text: "要判断だけ"

    get admin_annotation_path(@word)
    assert_select ".ann-queue-filter", count: 0
  end

  test "review=1 は要判断の語だけに絞り、sort は要判断(review)・確実(easy)な語を先頭にする" do
    sign_in_as(Admin.take)
    # haruhi=立項5/high(要判断でない)。bermuda に要判断(立項低・確信 low)の提案を足す
    AnnotationProposal.create!(word: words(:pending_bermuda),
      payload: { "confidence" => "low", "entry_score" => 2, "meaning" => "x。" })

    get admin_annotations_path(proposed: 1, review: 1)
    assert_redirected_to admin_annotation_path(words(:pending_bermuda), proposed: "1", review: "1")

    get admin_annotations_path(proposed: 1, sort: "review")
    assert_redirected_to admin_annotation_path(words(:pending_bermuda), proposed: "1", sort: "review")

    get admin_annotations_path(proposed: 1, sort: "easy")
    assert_redirected_to admin_annotation_path(words(:pending_haruhi), proposed: "1", sort: "easy")
  end

  test "並べ替え・絞り込みは保存後のキュー移動でも保たれる" do
    sign_in_as(Admin.take)
    AnnotationProposal.create!(word: words(:pending_bermuda),
      payload: { "confidence" => "low", "entry_score" => 2, "meaning" => "x。" })
    patch admin_annotation_path(@word), params: {
      proposed: "1", sort: "review",
      word: { word_senses_attributes: { "0" => { id: @sense.id, reading: @sense.reading } } }
    }
    assert_redirected_to admin_annotation_path(words(:pending_bermuda), proposed: "1", sort: "review")
  end

  # --- 提案あり語のロード時自動反映(Issue 64) ---
  test "?proposed=1 では明示操作なしで提案が自動反映される(保存はしない)" do
    sign_in_as(Admin.take)
    # show は annotation_proposals を joins したキューを辿る。素の id だと words.id と
    # annotation_proposals.id で曖昧になり StatementInvalid になっていた(その回帰防止を兼ねる)
    get admin_annotation_path(@word, proposed: 1)
    assert_response :success
    assert_select "textarea.js-meaning", text: /谷川流/
    assert_select "input.js-genre-value[value=?]", genres(:small_novel).id.to_s
    assert_nil @sense.reload.meaning
    assert_nil @sense.genre_id
  end

  test "通常表示や反映済みの提案では自動反映しない" do
    sign_in_as(Admin.take)
    # 通常表示(proposed なし)はスティッキー既定のまま。パネルには出るがフォームへは入れない
    get admin_annotation_path(@word)
    assert_select "textarea.js-meaning", text: /谷川流/, count: 0

    # 反映済みの提案は proposed でも入れない(二重反映を避ける)
    annotation_proposals(:haruhi_proposal).applied!
    @word.update!(annotated_at: Time.current)
    get admin_annotation_path(@word, proposed: 1)
    assert_response :success
    assert_select "textarea.js-meaning", text: /谷川流/, count: 0
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
    assert_select "input.js-genre-value[value=?]", word_senses(:murder).genre_id.to_s
  end

  # --- 1語の再調査(/reannotation へ渡す JSON) ---
  test "再調査用データは現在の内容とマスタを含む JSON を、コンソールと同じフレームに戻り導線つきで出す" do
    sign_in_as(Admin.take)
    word = words(:abc_murder)
    get reresearch_admin_annotation_path(word)

    assert_response :success
    json = JSON.parse(css_select("textarea#reresearch_json").first.text)
    assert_equal word.id, json["word_id"]
    assert_equal "saved", json["current"]["source"]
    assert_equal "人を殺す事件", json["current"]["senses"].first["meaning"]
    assert_includes json["masters"]["entity_types"], "書籍名"
    # コンソール(show)と同じ turbo フレームに入れるので、コピーしたらそのまま元の語へ戻れる
    assert_select "turbo-frame#annotation-console" do
      assert_select "a[href=?]", admin_annotation_path(word), text: I18n.t("admin.annotations.reresearch.back")
    end
  end

  private

  # haruhi の提案を、指定した名前の言語的特徴(該当部分 涼宮)を1つ持つ形にする。
  def propose_feature(name)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ {
        "meaning" => "谷川流のライトノベル。",
        "linguistic_features" => [ { "name" => name, "target" => "涼宮", "target_reading" => "すずみや" } ]
      } ]
    })
  end
end
