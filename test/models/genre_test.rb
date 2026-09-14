require "test_helper"

class GenreTest < ActiveSupport::TestCase
  test "self_and_ancestors は大→中→小の順に並び、root_genre は大分類を返す" do
    assert_equal [ genres(:large_literature), genres(:medium_japanese), genres(:small_novel) ],
                 genres(:small_novel).self_and_ancestors
    assert_equal genres(:large_literature), genres(:small_novel).root_genre
  end

  # --- name のバリデーション ---
  test "name は必須で、同じ親の下(親を持たない大分類同士を含む)では一意" do
    blank = Genre.new(level: :large, name: "")
    assert_not blank.valid?
    assert blank.errors.added?(:name, :blank)

    [ Genre.new(parent: genres(:medium_japanese), level: :small, name: genres(:small_novel).name),
      Genre.new(level: :large, name: genres(:large_literature).name) ].each do |duplicate|
      assert_not duplicate.valid?, "#{duplicate.name}(#{duplicate.level})の重複を許している"
      assert duplicate.errors.added?(:name, :taken, value: duplicate.name)
    end
  end

  test "親が異なれば同名でも有効" do
    other_medium = Genre.create!(parent: genres(:large_literature), level: :medium, name: "西洋文学")
    assert Genre.new(parent: other_medium, level: :small, name: genres(:small_novel).name).valid?
  end

  # --- level と parent の整合性 ---
  test "階層と親の組み合わせが合わないと無効" do
    {
      must_be_blank_for_large: Genre.new(parent: genres(:large_literature), level: :large, name: "歴史"),
      required_for_non_large: Genre.new(level: :medium, name: "日本史"),
      level_mismatch: Genre.new(parent: genres(:large_literature), level: :small, name: "純文学") # 小の親に大
    }.each do |error, genre|
      assert_not genre.valid?, "#{error} で弾かれていない"
      assert genre.errors.added?(:parent, error)
    end
  end

  # --- 削除・タグ統括管理(usage_count / deletable? / merge_into!) ---
  test "usage_count は配下の語義数を階層で積み上げる" do
    assert_equal 1, genres(:small_novel).usage_count
    assert_equal 1, genres(:medium_japanese).usage_count
    assert_equal 1, genres(:large_literature).usage_count
  end

  test "子も語義も持たないジャンルだけ削除できる" do
    large = genres(:large_literature)
    assert_not large.deletable?
    assert_not large.destroy, "子を持つジャンルが消えてしまった"
    assert Genre.exists?(large.id)
    assert_not genres(:small_novel).deletable? # 語義が付いている

    leaf = Genre.create!(name: "詩", level: :small, parent: genres(:medium_japanese))
    assert leaf.deletable?
  end

  test "同じ階層の小分類を統合すると語義が付け替わる" do
    other = Genre.create!(name: "随筆", level: :small, parent: genres(:medium_japanese))
    genres(:small_novel).merge_into!(other)
    assert_not Genre.exists?(genres(:small_novel).id)
    assert_equal other, word_senses(:murder).reload.genre
  end

  test "中分類を統合すると子ジャンルが統合先へ移る" do
    target_medium = Genre.create!(name: "英米文学", level: :medium, parent: genres(:large_literature))
    genres(:medium_japanese).merge_into!(target_medium)
    assert_not Genre.exists?(genres(:medium_japanese).id)
    assert_equal target_medium, genres(:small_novel).reload.parent
  end

  test "統合先に同名の子があれば子同士を統合する" do
    # 統合で消えるジャンルの id は、fixture アクセサが DB を引く前に控えておく。
    medium_japanese_id = genres(:medium_japanese).id
    small_novel_id = genres(:small_novel).id
    medium2 = Genre.create!(name: "近代文学", level: :medium, parent: genres(:large_literature))
    novel2 = Genre.create!(name: "小説", level: :small, parent: medium2)
    Genre.find(medium_japanese_id).merge_into!(medium2)
    assert_not Genre.exists?(medium_japanese_id)
    assert_not Genre.exists?(small_novel_id)
    assert_equal novel2, word_senses(:murder).reload.genre
  end

  test "階層の違うジャンル同士は統合できない" do
    assert_raises(ArgumentError) { genres(:small_novel).merge_into!(genres(:medium_japanese)) }
  end
end
