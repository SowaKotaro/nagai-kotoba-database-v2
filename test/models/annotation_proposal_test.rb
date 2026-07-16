require "test_helper"

# Claude の提案(下書き)。payload の読み出しとマスタ名の解決(Issue 38)。
class AnnotationProposalTest < ActiveSupport::TestCase
  setup { @proposal = annotation_proposals(:haruhi_proposal) }

  test "payload から提案値を読み出せる" do
    assert_match "谷川流", @proposal.meaning
    assert_equal %w[文学 日本文学 小説], @proposal.genre_path
    assert_equal "書籍名", @proposal.entity_type_name
    assert_equal "名詞", @proposal.part_of_speech_name
    assert_equal %w[和語], @proposal.word_origin_names
    assert_equal [ "ハルヒ" ], @proposal.variants.map { |v| v["surface"] }
    assert_equal "high", @proposal.confidence
    assert_match "シリーズ第1作", @proposal.notes
  end

  test "ジャンルパスを木から末端(小分類)まで解決できる" do
    assert_equal genres(:small_novel), @proposal.resolved_genre
  end

  test "存在しない・途中までのジャンルパスは解決しない(新設候補)" do
    @proposal.payload["genre_path"] = %w[文学 日本文学 存在しない小分類]
    assert_nil @proposal.resolved_genre

    # 途中(中分類)までしか無いパスも、末端が小分類でないため解決しない
    @proposal.payload["genre_path"] = %w[文学 日本文学]
    assert_nil @proposal.resolved_genre
  end

  test "resolved_genre_chain は既存の木を辿れるところまでの鎖を返す" do
    # 末端まで一致 → [大, 中, 小]
    assert_equal [ genres(:large_literature), genres(:medium_japanese), genres(:small_novel) ],
                 @proposal.senses.first.resolved_genre_chain

    # 小分類だけ未登録 → 大・中まで([大, 中])。resolved_genre は nil のまま
    @proposal.payload["genre_path"] = %w[文学 日本文学 私小説]
    assert_equal [ genres(:large_literature), genres(:medium_japanese) ],
                 @proposal.senses.first.resolved_genre_chain
    assert_nil @proposal.senses.first.resolved_genre

    # 大分類から一致しない → 空配列
    @proposal.payload["genre_path"] = %w[無い大分類 中 小]
    assert_empty @proposal.senses.first.resolved_genre_chain
  end

  test "エンティティ・品詞・語種を名前で解決できる" do
    assert_equal entity_types(:book_title), @proposal.resolved_entity_type
    assert_equal parts_of_speech(:noun), @proposal.resolved_part_of_speech
    assert_equal [ word_origins(:wago) ], @proposal.resolved_word_origins.to_a
    assert_empty @proposal.unknown_word_origin_names
  end

  test "未知のマスタ名は解決せず新設候補として残る" do
    @proposal.payload["entity_type"] = "存在しないエンティティ"
    @proposal.payload["word_origins"] = %w[和語 タミル語]

    assert_nil @proposal.resolved_entity_type
    assert_equal %w[タミル語], @proposal.unknown_word_origin_names
  end

  test "立項スコアを読み出せて、3以下だけ懸念になる(Issue 39)" do
    assert_equal 5, @proposal.entry_score
    assert_not @proposal.entry_concern?

    @proposal.payload["entry_score"] = 3
    @proposal.payload["entry_notes"] = "慣用性にグレーがある。"
    assert_equal 3, @proposal.entry_score
    assert @proposal.entry_concern?
    assert_equal "慣用性にグレーがある。", @proposal.entry_notes
  end

  test "立項スコアが未評価・範囲外なら nil で、懸念にもならない" do
    @proposal.payload.delete("entry_score")
    assert_nil @proposal.entry_score
    assert_not @proposal.entry_concern?

    @proposal.payload["entry_score"] = 9
    assert_nil @proposal.entry_score
    assert_not @proposal.entry_concern?
  end

  test "語には提案は1件まで(上書き前提のユニーク制約)" do
    duplicate = AnnotationProposal.new(word: words(:pending_haruhi), payload: { "meaning" => "重複" })
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  # --- 複数語義(同音異義語・Issue 41) ---

  test "トップレベル形式は単一語義として1件の senses になる(後方互換)" do
    assert_equal 1, @proposal.senses.size
    assert_not @proposal.multiple_senses?
    assert_match "谷川流", @proposal.senses.first.meaning
  end

  test "payload に senses 配列があれば語義ごとに読み出せる" do
    @proposal.payload = {
      "senses" => [
        { "meaning" => "通俗心理学の用語。", "genre_path" => %w[文学 日本文学 小説], "part_of_speech" => "名詞" },
        { "meaning" => "同名のアイドルグループ。", "entity_type" => "書籍名", "reading" => "ピーターパンシンドローム" }
      ],
      "confidence" => "medium",
      "entry_score" => 4
    }
    assert @proposal.multiple_senses?
    assert_equal 2, @proposal.senses.size
    assert_equal "通俗心理学の用語。", @proposal.senses.first.meaning
    assert_equal genres(:small_novel), @proposal.senses.first.resolved_genre
    assert_equal "同名のアイドルグループ。", @proposal.senses.second.meaning
    assert_equal "ピーターパンシンドローム", @proposal.senses.second.reading
    # 語全体のメタは語義に依らず読める
    assert_equal "medium", @proposal.confidence
    assert_equal 4, @proposal.entry_score
    # 後方互換の委譲は先頭語義を指す
    assert_equal "通俗心理学の用語。", @proposal.meaning
  end

  # --- 言語的特徴の提案(Issue 63) ---

  test "senses の言語的特徴を name/target/target_reading で読み出せる" do
    @proposal.payload = {
      "senses" => [ {
        "meaning" => "テスト。",
        "linguistic_features" => [
          { "name" => "連濁", "target" => "涼宮", "target_reading" => "すずみや" }
        ]
      } ]
    }
    features = @proposal.senses.first.linguistic_features
    assert_equal 1, features.size
    assert_equal "連濁", features.first["name"]
    assert_equal "涼宮", features.first["target"]
    assert_equal linguistic_features(:rendaku),
                 @proposal.senses.first.resolved_linguistic_feature(features.first)
  end

  test "特徴は name/target/target_reading が揃ったものだけ返す(保存できない欠けは捨てる)" do
    @proposal.payload = {
      "senses" => [ {
        "linguistic_features" => [
          { "name" => "連濁", "target" => "涼宮", "target_reading" => "すずみや" }, # 揃い
          { "name" => "連濁", "target" => "涼宮" },                                # target_reading 欠け
          { "name" => "", "target" => "宮", "target_reading" => "みや" },          # name 欠け
          { "target" => "涼", "target_reading" => "すず" }                          # name 無し
        ]
      } ]
    }
    assert_equal 1, @proposal.senses.first.linguistic_features.size
  end

  test "未知の特徴名は解決せず nil(新設候補)" do
    @proposal.payload = {
      "senses" => [ {
        "linguistic_features" => [
          { "name" => "存在しない特徴", "target" => "涼宮", "target_reading" => "すずみや" }
        ]
      } ]
    }
    feature = @proposal.senses.first.linguistic_features.first
    assert_nil @proposal.senses.first.resolved_linguistic_feature(feature)
  end

  # --- 要判断フィルタ(Issue 67) ---
  test "needs_review は立項3以下か確信 low の提案に絞る" do
    # haruhi は 立項5/high なので対象外
    assert_not_includes AnnotationProposal.needs_review, @proposal

    @proposal.update!(payload: @proposal.payload.merge("entry_score" => 3))
    assert_includes AnnotationProposal.needs_review, @proposal

    # 立項が十分でも確信度 low なら要判断
    @proposal.update!(payload: @proposal.payload.merge("entry_score" => 5, "confidence" => "low"))
    assert_includes AnnotationProposal.needs_review, @proposal
  end
end
