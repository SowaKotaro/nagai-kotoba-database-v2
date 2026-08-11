require "test_helper"

# ジャンルフィルタ(1,131件のチップ)をフラグメントキャッシュに載せたことによる回帰を防ぐ。
#
# テスト環境は既定でキャッシュ無効(perform_caching = false)なので、
# 素の searches_controller_test では「キャッシュに載せたせいで壊れる」類のバグを
# 検出できない。ここだけ明示的にキャッシュを有効にして、
# 選択状態の混線とマスタ更新時の無効化を確かめる。
class SearchesGenreFilterCacheTest < ActionDispatch::IntegrationTest
  setup do
    @original_perform_caching = ActionController::Base.perform_caching
    @original_cache = Rails.cache
    ActionController::Base.perform_caching = true
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    ActionController::Base.perform_caching = @original_perform_caching
    Rails.cache = @original_cache
  end

  test "選択の違うリクエスト同士でキャッシュが混線しない" do
    novel = genres(:small_novel)
    other = another_small_genre

    get search_path, params: { genre_id: [ novel.id ] }
    assert_checked novel
    assert_not_checked other

    # 別の選択で開く。前のリクエストのキャッシュが返ってはいけない。
    get search_path, params: { genre_id: [ other.id ] }
    assert_checked other
    assert_not_checked novel

    # 条件なしへ戻すと、どれも選択されていない状態に戻る。
    get search_path
    assert_not_checked novel
    assert_not_checked other
    assert_select "details.genre-fold[open]", count: 0
  end

  test "選択の順序が違っても同じ結果になる" do
    novel = genres(:small_novel)
    other = another_small_genre

    get search_path, params: { genre_id: [ novel.id, other.id ] }
    first = genre_filter_fragment

    get search_path, params: { genre_id: [ other.id, novel.id ] }
    assert_equal first, genre_filter_fragment
  end

  test "ジャンルを改名するとキャッシュが更新される" do
    get search_path
    assert_select ".check-chip__face", text: genres(:small_novel).name

    genres(:small_novel).update!(name: "改名した小分類")

    get search_path
    assert_select ".check-chip__face", text: "改名した小分類"
  end

  test "ジャンルを追加するとキャッシュが更新される" do
    get search_path
    assert_select ".check-chip__face", text: "追加した小分類", count: 0

    Genre.create!(name: "追加した小分類", parent: genres(:medium_japanese), level: :small)

    get search_path
    assert_select ".check-chip__face", text: "追加した小分類"
  end

  test "ジャンルを削除するとキャッシュが更新される" do
    added = Genre.create!(name: "消す小分類", parent: genres(:medium_japanese), level: :small)
    get search_path
    assert_select ".check-chip__face", text: "消す小分類"

    added.destroy!

    get search_path
    assert_select ".check-chip__face", text: "消す小分類", count: 0
  end

  private

  # フィクスチャの小分類は1件だけなので、混線の確認用にもう1件だけ足す。
  def another_small_genre
    Genre.create!(name: "混線確認用の小分類", parent: genres(:medium_japanese), level: :small)
  end

  def assert_checked(genre)
    assert_select "input[type=checkbox][name=?][value=?][checked]", "genre_id[]", genre.id.to_s
  end

  def assert_not_checked(genre)
    assert_select "input[type=checkbox][name=?][value=?][checked]", "genre_id[]", genre.id.to_s, count: 0
  end

  # CSRF トークンなど毎回変わる要素を巻き込まずに比べるため、区画だけを取り出す。
  def genre_filter_fragment
    response.body[/<div class="genre-filter".*?<\/fieldset>/m] ||
      flunk("ジャンルフィルタの区画が描画されていない")
  end
end
