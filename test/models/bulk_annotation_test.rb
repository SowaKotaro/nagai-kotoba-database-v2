require "test_helper"

# 一覧で選択した語への共通属性の一括適用(Issue 37)。
class BulkAnnotationTest < ActiveSupport::TestCase
  setup do
    @haruhi = words(:pending_haruhi)   # 単一語義・未注釈
    @bermuda = words(:pending_bermuda) # 単一語義・未注釈
  end

  test "選択した単一語義の語に、指定した項目だけを適用する" do
    result = BulkAnnotation.new(
      word_ids: [ @haruhi.id, @bermuda.id ],
      genre_id: genres(:small_novel).id,
      entity_type_id: entity_types(:book_title).id,
      meaning_template: "テンプレの意味。"
    ).apply

    assert_equal 2, result.applied
    assert_equal 0, result.skipped

    [ word_senses(:pending), word_senses(:pending2) ].each do |sense|
      sense.reload
      assert_equal genres(:small_novel).id, sense.genre_id
      assert_equal entity_types(:book_title).id, sense.entity_type_id
      assert_equal "テンプレの意味。", sense.meaning
      # 未指定の項目(品詞)は変更しない
      assert_nil sense.part_of_speech_id
    end
  end

  test "語種は複数まとめて適用できる" do
    BulkAnnotation.new(
      word_ids: [ @haruhi.id ],
      word_origin_ids: [ word_origins(:wago).id, word_origins(:kango).id ]
    ).apply

    assert_equal [ word_origins(:kango).id, word_origins(:wago).id ].sort,
                 word_senses(:pending).reload.word_origin_ids.sort
  end

  test "既定では注釈済みにしない(確定事項4)" do
    BulkAnnotation.new(word_ids: [ @haruhi.id ], genre_id: genres(:small_novel).id).apply
    assert_nil @haruhi.reload.annotated_at
  end

  test "mark_annotated を指定すると注釈済みになる" do
    BulkAnnotation.new(
      word_ids: [ @haruhi.id ], genre_id: genres(:small_novel).id, mark_annotated: "1"
    ).apply
    assert_not_nil @haruhi.reload.annotated_at
  end

  test "複数語義の語は誤爆防止のためスキップして数える" do
    # 2つ目の語義を足して同音異義語の状態にする
    @haruhi.word_senses.create!(reading: "すずみやはるひのゆううつべつぎ")

    result = BulkAnnotation.new(
      word_ids: [ @haruhi.id, @bermuda.id ], genre_id: genres(:small_novel).id
    ).apply

    assert_equal 1, result.applied
    assert_equal 1, result.skipped
    assert_nil word_senses(:pending).reload.genre_id
    assert_equal genres(:small_novel).id, word_senses(:pending2).reload.genre_id
  end

  test "語が選択されていないとバリデーションエラー" do
    bulk = BulkAnnotation.new(word_ids: [], genre_id: genres(:small_novel).id)
    assert_not bulk.valid?
    assert_includes bulk.errors.full_messages.join, "選択されていません"
  end

  test "適用する属性が無いとバリデーションエラー" do
    bulk = BulkAnnotation.new(word_ids: [ @haruhi.id ])
    assert_not bulk.valid?
    assert_includes bulk.errors.full_messages.join, "属性"
  end
end
