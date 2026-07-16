require "test_helper"

# 提案の「新設候補」マスタのワンタップ作成(Issue 66)。
class ProposedMasterCreationTest < ActiveSupport::TestCase
  # payload から先頭語義の SenseProposal を作る(提案は保存不要)。
  def sense_with(payload)
    AnnotationProposal.new(payload: payload).senses.first
  end

  test "エンティティを提案名で作成する" do
    sense = sense_with("entity_type" => "架空エンティティ種別")
    assert_difference -> { EntityType.count } => 1 do
      created = ProposedMasterCreation.new(sense, "entity_type").create!
      assert_equal "架空エンティティ種別", created.name
    end
  end

  test "品詞を提案名で作成する" do
    sense = sense_with("part_of_speech" => "架空品詞")
    assert_difference -> { PartOfSpeech.count } => 1 do
      ProposedMasterCreation.new(sense, "part_of_speech").create!
    end
  end

  test "語種は指定した name で作成する(候補が複数ある種別)" do
    sense = sense_with("word_origins" => %w[和語 タミル語])
    assert_difference -> { WordOrigin.count } => 1 do
      created = ProposedMasterCreation.new(sense, "word_origin", "タミル語").create!
      assert_equal "タミル語", created.name
    end
  end

  test "ジャンル小分類を、解決できた中分類の下に小分類として作る" do
    sense = sense_with("genre_path" => %w[文学 日本文学 私小説])
    assert_difference -> { Genre.count } => 1 do
      created = ProposedMasterCreation.new(sense, "genre").create!
      assert created.small?
      assert_equal genres(:medium_japanese), created.parent
      assert_equal "私小説", created.name
    end
  end

  test "中分類まで解決できないジャンルは作れない(Error)" do
    sense = sense_with("genre_path" => %w[無い大分類 無い中分類 小])
    assert_raises(ProposedMasterCreation::Error) do
      ProposedMasterCreation.new(sense, "genre").create!
    end
  end

  test "未知の field は Error" do
    sense = sense_with("entity_type" => "x")
    assert_raises(ProposedMasterCreation::Error) do
      ProposedMasterCreation.new(sense, "linguistic_feature").create!
    end
  end

  test "名前が空なら作らない(Error)" do
    assert_raises(ProposedMasterCreation::Error) do
      ProposedMasterCreation.new(sense_with({}), "entity_type").create!
    end
  end

  test "既存名なら重複作成しない(find_or_create)" do
    sense = sense_with("entity_type" => entity_types(:book_title).name)
    assert_no_difference -> { EntityType.count } do
      assert_equal entity_types(:book_title), ProposedMasterCreation.new(sense, "entity_type").create!
    end
  end
end
