require "test_helper"

# アノテーション・デッキ(まとめてアノテーション)。キューの先頭から複数件を1画面に載せ、
# 1回の送信で語ごとに保存する(通った語だけ公開し、落ちた語はデッキに残す)。
class Admin::AnnotationDecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @haruhi = words(:pending_haruhi)
    @bermuda = words(:pending_bermuda)
    @haruhi_sense = word_senses(:pending)
    @bermuda_sense = word_senses(:pending2)
  end

  # --- 認可: 未認証は弾く ---
  test "未認証だとデッキはログインへリダイレクト" do
    get admin_annotation_deck_path
    assert_redirected_to new_session_path
  end

  test "未認証だとまとめて保存できない" do
    patch admin_annotation_deck_path, params: { deck: deck_params_for(@haruhi, @haruhi_sense) }
    assert_redirected_to new_session_path
    assert_nil @haruhi.reload.annotated_at
  end

  # --- 表示 ---
  test "入口は1語コンソールと同じく提案付きのキューへ寄せる" do
    sign_in_as(Admin.take)
    get admin_annotation_deck_path
    assert_redirected_to admin_annotation_deck_path(proposed: 1)
  end

  test "未対応の語をまとめて1画面に載せる" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).applied! # 提案キューへの誘導を外す
    get admin_annotation_deck_path
    assert_response :success
    assert_select ".deck-card", 2
    # 語ごとに deck[<語id>][...] で束ねて送る
    assert_select "textarea[name=?]", "deck[#{@haruhi.id}][word_senses_attributes][0][reading]"
    assert_select "textarea[name=?]", "deck[#{@bermuda.id}][word_senses_attributes][0][reading]"
  end

  test "枚数は size で絞れる" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).applied!
    get admin_annotation_deck_path(size: 1)
    assert_response :success
    assert_select ".deck-card", 1
  end

  test "未承認の提案はカードに反映済みで開く" do
    sign_in_as(Admin.take)
    get admin_annotation_deck_path(proposed: 1)
    assert_response :success
    assert_select "textarea[name=?]", "deck[#{@haruhi.id}][word_senses_attributes][0][meaning]",
                  text: /谷川流のライトノベル/
  end

  test "未対応の語が無ければ空の案内を出す" do
    sign_in_as(Admin.take)
    Word.annotation_pending.find_each { |word| word.update!(annotation_status: :on_hold) }
    get admin_annotation_deck_path
    assert_response :success
    assert_select ".ann-done__lead"
    assert_select ".deck-card", 0
  end

  # --- まとめ保存 ---
  test "まとめて保存すると全件が注釈済みになり提案は反映済みになる" do
    sign_in_as(Admin.take)
    params = deck_params_for(@haruhi, @haruhi_sense).merge(deck_params_for(@bermuda, @bermuda_sense))

    patch admin_annotation_deck_path, params: { deck: params }
    assert_redirected_to admin_annotation_deck_path
    assert_equal "2 件をまとめて保存しました。", flash[:notice]

    assert @haruhi.reload.annotation_done?
    assert_not_nil @haruhi.annotated_at
    assert @bermuda.reload.annotation_done?
    assert annotation_proposals(:haruhi_proposal).reload.applied?
  end

  test "絞り込み・並べ替えは保存後のデッキにも引き継ぐ" do
    sign_in_as(Admin.take)
    patch admin_annotation_deck_path,
          params: { deck: deck_params_for(@haruhi, @haruhi_sense), proposed: "1", sort: "easy" }
    assert_redirected_to admin_annotation_deck_path(proposed: "1", sort: "easy")
  end

  test "エラーのある語だけデッキに残し、通った語は保存する" do
    sign_in_as(Admin.take)
    valid = deck_params_for(@haruhi, @haruhi_sense)
    invalid = deck_params_for(@bermuda, @bermuda_sense)
    invalid[@bermuda.id.to_s][:word_senses_attributes]["0"][:reading] = "" # 読みは必須

    patch admin_annotation_deck_path, params: { deck: valid.merge(invalid) }
    assert_response :unprocessable_entity

    assert @haruhi.reload.annotation_done?, "通った語は保存される"
    assert @bermuda.reload.annotation_pending?, "落ちた語は未対応のまま"
    assert_match "1 件を保存しました", flash[:alert]
    # 落ちた語だけがデッキに残り、エラーが見える
    assert_select ".deck-card", 1
    assert_select ".error-explanation"
    assert_select "textarea[name=?]", "deck[#{@bermuda.id}][word_senses_attributes][0][reading]"
  end

  test "存在しない語 id は無視する" do
    sign_in_as(Admin.take)
    params = deck_params_for(@haruhi, @haruhi_sense).merge(
      "0" => { word_senses_attributes: { "0" => { reading: "ゆうれい" } } }
    )
    assert_no_difference -> { Word.count } do
      patch admin_annotation_deck_path, params: { deck: params }
    end
    assert_redirected_to admin_annotation_deck_path
    assert_equal "1 件をまとめて保存しました。", flash[:notice]
  end

  # --- 提案の新設候補マスタのその場作成(Issue 66 のデッキ版) ---
  test "デッキの提案欄には新設候補の作成ボタンが出る" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "meaning" => "x。", "entity_type" => "架空種別" } ]
    })
    get admin_annotation_deck_path(proposed: 1)
    assert_response :success
    assert_select "input[type=submit][formaction*=?]", "create_master"
  end

  test "create_master はマスタを作り、入力を保ったままカードへ入れる" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "meaning" => "x。", "entity_type" => "架空種別" } ]
    })
    params = deck_params_for(@haruhi, @haruhi_sense)
    params[@haruhi.id.to_s][:word_senses_attributes]["0"][:meaning] = "入力中の意味"

    assert_difference -> { EntityType.count } => 1 do
      patch create_master_admin_annotation_deck_path(word_id: @haruhi.id, field: "entity_type"),
            params: { deck: params }
    end
    assert_response :success

    created = EntityType.find_by(name: "架空種別")
    assert_select "input[type=radio][value=?][checked]", created.id.to_s
    # 送った入力はそのまま残る(他のカードの入力も消さない)
    assert_select "textarea[name=?]", "deck[#{@haruhi.id}][word_senses_attributes][0][meaning]",
                  text: "入力中の意味"
    assert_not @haruhi.reload.annotation_done?, "その場作成では語を保存しない"
  end

  test "create_master でジャンル小分類を中分類の下に作り、カードのジャンルに入れる" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "genre_path" => %w[文学 日本文学 私小説] } ]
    })
    assert_difference -> { Genre.count } => 1 do
      patch create_master_admin_annotation_deck_path(word_id: @haruhi.id, field: "genre"),
            params: { deck: deck_params_for(@haruhi, @haruhi_sense) }
    end
    created = Genre.find_by(name: "私小説")
    assert_equal genres(:medium_japanese), created.parent
    assert_select "input[name=?][value=?]",
                  "deck[#{@haruhi.id}][word_senses_attributes][0][genre_id]", created.id.to_s
  end

  test "create_master で語種を指定名で作り、カードで選択済みにする" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "word_origins" => %w[和語 タミル語] } ]
    })
    assert_difference -> { WordOrigin.count } => 1 do
      patch create_master_admin_annotation_deck_path(word_id: @haruhi.id, field: "word_origin",
                                                     name: "タミル語"),
            params: { deck: deck_params_for(@haruhi, @haruhi_sense) }
    end
    created = WordOrigin.find_by(name: "タミル語")
    assert_select "input[type=checkbox][value=?][checked]", created.id.to_s
  end

  test "create_master は作れない指定でも入力を残したまま知らせる" do
    sign_in_as(Admin.take)
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "genre_path" => %w[無い 無い 無い] } ]
    })
    params = deck_params_for(@haruhi, @haruhi_sense)
    params[@haruhi.id.to_s][:word_senses_attributes]["0"][:meaning] = "入力中の意味"

    assert_no_difference -> { Genre.count } do
      patch create_master_admin_annotation_deck_path(word_id: @haruhi.id, field: "genre"),
            params: { deck: params }
    end
    assert_response :success
    assert_equal I18n.t("admin.annotations.create_master_failed"), flash[:alert]
    assert_select "textarea[name=?]", "deck[#{@haruhi.id}][word_senses_attributes][0][meaning]",
                  text: "入力中の意味"
  end

  test "未認証は create_master できない" do
    annotation_proposals(:haruhi_proposal).update!(payload: {
      "senses" => [ { "entity_type" => "架空種別" } ]
    })
    assert_no_difference -> { EntityType.count } do
      patch create_master_admin_annotation_deck_path(word_id: @haruhi.id, field: "entity_type"),
            params: { deck: deck_params_for(@haruhi, @haruhi_sense) }
    end
    assert_redirected_to new_session_path
  end

  private

  # 1語分の送信パラメータ(既存の語義の読みをそのまま送る)。
  def deck_params_for(word, sense)
    { word.id.to_s => {
      surface: word.surface,
      word_senses_attributes: { "0" => { id: sense.id, reading: sense.reading } }
    } }
  end
end
