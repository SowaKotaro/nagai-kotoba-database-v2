require "test_helper"

class TagKindTest < ActiveSupport::TestCase
  test "all は5種を表示順で返す" do
    assert_equal %w[genres entity_types parts_of_speech word_origins linguistic_features],
                 TagKind.all.map(&:key)
  end

  test "find は既知の種別を返す" do
    assert_equal EntityType, TagKind.find("entity_types").model
  end

  test "find は未知の種別で RecordNotFound(任意モデルを掴ませない)" do
    assert_raises(ActiveRecord::RecordNotFound) { TagKind.find("admins") }
    assert_raises(ActiveRecord::RecordNotFound) { TagKind.find("Word") }
  end

  test "hierarchical? はジャンルだけ真" do
    assert TagKind.find("genres").hierarchical?
    assert_not TagKind.find("entity_types").hierarchical?
  end

  test "usage_counts は種別ごとに id=>使用件数 を返す" do
    assert_equal 1, TagKind.find("entity_types").usage_counts[entity_types(:book_title).id]
    assert_equal 2, TagKind.find("parts_of_speech").usage_counts[parts_of_speech(:noun).id]
    assert_equal 1, TagKind.find("word_origins").usage_counts[word_origins(:kango).id]
    assert_equal 1, TagKind.find("linguistic_features").usage_counts[linguistic_features(:rendaku).id]
  end

  test "ジャンルの records は階層(木)を深さ優先でたどった順に並ぶ" do
    # 別系統(歴史 › 日本史)を足して、大分類ごとにその配下がまとまることを確認する。
    history = Genre.create!(name: "歴史", level: :large)
    jp_history = Genre.create!(name: "日本史", level: :medium, parent: history)
    order = TagKind.find("genres").records.map(&:name)
    # 文学系(大→中→小)がひとかたまり、歴史系がひとかたまりで、大分類は名前順。
    assert_equal %w[文学 日本文学 小説 歴史 日本史], order
    assert jp_history.persisted?
  end

  test "ジャンルの usage_counts は階層で積み上げる" do
    counts = TagKind.find("genres").usage_counts
    assert_equal 1, counts[genres(:small_novel).id]
    assert_equal 1, counts[genres(:medium_japanese).id]
    assert_equal 1, counts[genres(:large_literature).id]
  end

  test "deletable_ids は未使用のみ(ジャンルは子を持たないもの)" do
    kind = TagKind.find("entity_types")
    records = kind.records.to_a
    ids = kind.deletable_ids(records, kind.usage_counts)
    assert_includes ids, entity_types(:person_name).id
    assert_not_includes ids, entity_types(:book_title).id

    gkind = TagKind.find("genres")
    grecords = gkind.records.to_a
    gids = gkind.deletable_ids(grecords, gkind.usage_counts)
    assert_not_includes gids, genres(:large_literature).id # 子あり
    assert_not_includes gids, genres(:small_novel).id       # 語義あり
  end
end
