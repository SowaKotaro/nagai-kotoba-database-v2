require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
class Admin::BulkAnnotationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @haruhi = words(:pending_haruhi)
    @bermuda = words(:pending_bermuda)
  end

  test "未認証だと一括適用できずログインへリダイレクト" do
    post admin_bulk_annotation_path, params: {
      bulk_annotation: { word_ids: [ @haruhi.id ], genre_id: genres(:small_novel).id }
    }
    assert_redirected_to new_session_path
    assert_nil word_senses(:pending).reload.genre_id
  end

  test "選択した語に一括適用し、検索・絞り込みを保って一覧へ戻る" do
    sign_in_as(Admin.take)
    post admin_bulk_annotation_path, params: {
      q: "ハルヒ", status: "annotation_pending",
      bulk_annotation: { word_ids: [ @haruhi.id ], genre_id: genres(:small_novel).id }
    }

    assert_redirected_to admin_words_path(q: "ハルヒ", status: "annotation_pending")
    assert_equal "1 語に適用しました。", flash[:notice]
    assert_equal genres(:small_novel).id, word_senses(:pending).reload.genre_id
    # 既定では注釈済みにしない
    assert_nil @haruhi.reload.annotated_at
  end

  test "タグ絞り込みの条件も保って一覧へ戻る" do
    sign_in_as(Admin.take)
    post admin_bulk_annotation_path, params: {
      genre_id: genres(:large_literature).id, part_of_speech_id: parts_of_speech(:noun).id,
      bulk_annotation: { word_ids: [ @haruhi.id ], part_of_speech_id: parts_of_speech(:noun).id }
    }

    assert_redirected_to admin_words_path(genre_id: genres(:large_literature).id,
                                          part_of_speech_id: parts_of_speech(:noun).id)
    assert_equal parts_of_speech(:noun).id, word_senses(:pending).reload.part_of_speech_id
  end

  test "複数語義の語はスキップし、件数をフラッシュで知らせる" do
    sign_in_as(Admin.take)
    @haruhi.word_senses.create!(reading: "すずみやはるひのゆううつべつぎ")

    post admin_bulk_annotation_path, params: {
      bulk_annotation: { word_ids: [ @haruhi.id, @bermuda.id ], genre_id: genres(:small_novel).id }
    }

    assert_redirected_to admin_words_path
    assert_equal "1 語に適用しました（複数語義のためスキップ 1 語）。", flash[:notice]
  end

  test "適用する属性が無いとエラーを知らせて一覧へ戻す" do
    sign_in_as(Admin.take)
    post admin_bulk_annotation_path, params: { bulk_annotation: { word_ids: [ @haruhi.id ] } }

    assert_redirected_to admin_words_path
    assert_match "属性", flash[:alert]
  end
end
