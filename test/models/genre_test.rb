require "test_helper"

class GenreTest < ActiveSupport::TestCase
  # --- 正常系 ---
  test "3階層(大→中→小)が有効に作成できる" do
    large = genres(:large_literature)
    medium = genres(:medium_japanese)
    small = genres(:small_novel)

    assert large.large?
    assert medium.medium?
    assert small.small?
    assert_equal large, medium.parent
    assert_equal medium, small.parent
  end

  test "children で子ジャンルを辿れる" do
    assert_includes genres(:large_literature).children, genres(:medium_japanese)
  end

  test "self_and_ancestors は大→中→小の順で返す" do
    assert_equal [ genres(:large_literature), genres(:medium_japanese), genres(:small_novel) ],
                 genres(:small_novel).self_and_ancestors
  end

  test "root_genre は大分類を返す" do
    assert_equal genres(:large_literature), genres(:small_novel).root_genre
  end

  # --- name のバリデーション ---
  test "name が空だと無効" do
    genre = Genre.new(level: :large, name: "")
    assert_not genre.valid?
    assert genre.errors.added?(:name, :blank)
  end

  test "同じ親の下で同名は無効" do
    dup = Genre.new(parent: genres(:medium_japanese), level: :small, name: genres(:small_novel).name)
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: genres(:small_novel).name)
  end

  test "親が異なれば同名でも有効" do
    other_medium = Genre.create!(parent: genres(:large_literature), level: :medium, name: "西洋文学")
    genre = Genre.new(parent: other_medium, level: :small, name: genres(:small_novel).name)
    assert genre.valid?
  end

  test "level1(大分類)同士の同名重複はモデルで防ぐ" do
    dup = Genre.new(level: :large, name: genres(:large_literature).name)
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: genres(:large_literature).name)
  end

  # --- level と parent の整合性 ---
  test "大分類が親を持つと無効" do
    genre = Genre.new(parent: genres(:large_literature), level: :large, name: "歴史")
    assert_not genre.valid?
    assert genre.errors.added?(:parent, :must_be_blank_for_large)
  end

  test "中分類が親を持たないと無効" do
    genre = Genre.new(level: :medium, name: "日本史")
    assert_not genre.valid?
    assert genre.errors.added?(:parent, :required_for_non_large)
  end

  test "親の階層が1つ上でないと無効(小の親に大を指定)" do
    genre = Genre.new(parent: genres(:large_literature), level: :small, name: "純文学")
    assert_not genre.valid?
    assert genre.errors.added?(:parent, :level_mismatch)
  end

  test "level が不正な値だと enum で例外" do
    assert_raises(ArgumentError) { Genre.new(level: 9) }
  end

  # --- 子を持つジャンルの削除 ---
  test "子を持つジャンルは削除できない" do
    large = genres(:large_literature)
    assert_not large.destroy
    assert Genre.exists?(large.id)
  end
end
