require "test_helper"

# マスタ seed のカタログ(Issue 49: deploy:seed × リネームの重複再発防止)。
class SeedCatalogTest < ActiveSupport::TestCase
  # ---- apply_simple!(単純マスタ) ----

  test "apply_simple! は不足している名前を作成し、冪等" do
    capture_io { SeedCatalog.apply_simple!(WordOrigin, names: [ "日本語", "中国語" ]) }

    assert WordOrigin.exists?(name: "日本語")
    count = WordOrigin.count
    capture_io { SeedCatalog.apply_simple!(WordOrigin, names: [ "日本語", "中国語" ]) }
    assert_equal count, WordOrigin.count
  end

  test "apply_simple! はリネーム追従マップで旧名レコードを改名する(他環境の追従)" do
    WordOrigin.create!(name: "オランダ語")

    capture_io { SeedCatalog.apply_simple!(WordOrigin, names: [ "蘭語" ], renames: { "オランダ語" => "蘭語" }) }

    assert_not WordOrigin.exists?(name: "オランダ語")
    assert_equal 1, WordOrigin.where(name: "蘭語").count
  end

  test "apply_simple! は UI リネーム済みの環境でも旧名を再作成しない(重複再発防止の本丸)" do
    # 本番で「オランダ語」→「蘭語」に UI リネーム済みで、カタログも更新された状態を再現
    WordOrigin.create!(name: "蘭語")

    capture_io { SeedCatalog.apply_simple!(WordOrigin, names: [ "蘭語" ], renames: { "オランダ語" => "蘭語" }) }

    assert_not WordOrigin.exists?(name: "オランダ語")
    assert_equal 1, WordOrigin.where(name: "蘭語").count
  end

  test "apply_simple! は移行先が既に存在するときは改名せず警告してスキップする" do
    WordOrigin.create!(name: "オランダ語")
    WordOrigin.create!(name: "蘭語")

    out, _err = capture_io do
      SeedCatalog.apply_simple!(WordOrigin, names: [ "蘭語" ], renames: { "オランダ語" => "蘭語" })
    end

    # どちらも残す(データが付いている可能性があるため、統合は /admin/tags に委ねる)
    assert WordOrigin.exists?(name: "オランダ語")
    assert WordOrigin.exists?(name: "蘭語")
    assert_includes out, "スキップ"
  end

  # ---- apply_genres!(階層マスタ) ----

  test "apply_genres! は大・中の木を作成し、冪等" do
    tree = { "試験大分類" => [ "試験中分類A", "試験中分類B" ] }

    capture_io { SeedCatalog.apply_genres!(tree: tree) }

    large = Genre.large.find_by!(name: "試験大分類")
    assert_equal [ "試験中分類A", "試験中分類B" ], large.children.order(:id).pluck(:name)

    count = Genre.count
    capture_io { SeedCatalog.apply_genres!(tree: tree) }
    assert_equal count, Genre.count
  end

  test "apply_genres! は大分類をパスで改名でき、子は付いたまま" do
    capture_io { SeedCatalog.apply_genres!(tree: { "旧大分類" => [ "中X" ] }) }

    capture_io do
      SeedCatalog.apply_genres!(tree: { "新大分類" => [ "中X" ] }, renames: { "旧大分類" => "新大分類" })
    end

    assert_not Genre.exists?(name: "旧大分類")
    large = Genre.large.find_by!(name: "新大分類")
    assert_equal [ "中X" ], large.children.pluck(:name)
  end

  test "apply_genres! は中分類を 大/中 のパスで改名できる" do
    capture_io { SeedCatalog.apply_genres!(tree: { "大Y" => [ "旧中" ] }) }

    capture_io do
      SeedCatalog.apply_genres!(tree: { "大Y" => [ "新中" ] }, renames: { "大Y/旧中" => "新中" })
    end

    assert_equal [ "新中" ], Genre.large.find_by!(name: "大Y").children.pluck(:name)
  end

  test "apply_genres! は移行先が同じ親の下に存在するときは改名せず警告してスキップする" do
    capture_io { SeedCatalog.apply_genres!(tree: { "大Z" => [ "中1", "中2" ] }) }

    out, _err = capture_io do
      SeedCatalog.apply_genres!(tree: { "大Z" => [ "中2" ] }, renames: { "大Z/中1" => "中2" })
    end

    assert_equal [ "中1", "中2" ], Genre.large.find_by!(name: "大Z").children.order(:id).pluck(:name)
    assert_includes out, "スキップ"
  end

  # ---- seeded?(管理画面の seed 印・警告用) ----

  test "seeded? はカタログ収載の名前だけ true" do
    assert SeedCatalog.seeded?("word_origins", word_origins(:eigo)) # 英語: カタログ収載
    assert_not SeedCatalog.seeded?("word_origins", word_origins(:wago)) # 和語: カタログ外(UI 追加扱い)
    assert_not SeedCatalog.seeded?("entity_types", entity_types(:person_name)) # 種別ごと seed 管理外
  end

  test "seeded? のジャンル判定は階層と親を見る" do
    capture_io { SeedCatalog.apply_genres!(tree: { "言語" => [ "音韻論" ] }) }
    large = Genre.large.find_by!(name: "言語")
    medium = large.children.find_by!(name: "音韻論")
    small = Genre.create!(parent: medium, level: :small, name: "テスト小分類")

    assert SeedCatalog.seeded?("genres", large)
    assert SeedCatalog.seeded?("genres", medium)
    assert_not SeedCatalog.seeded?("genres", small) # 小分類は seed 管理しない
    assert_not SeedCatalog.seeded?("genres", genres(:large_literature)) # カタログ外の大分類

    # 一覧表示と同じ genre_index 経由でも同じ判定(親参照の N+1 回避経路)
    index = Genre.all.index_by(&:id)
    assert SeedCatalog.seeded?("genres", medium, genre_index: index)
    assert_not SeedCatalog.seeded?("genres", genres(:medium_japanese), genre_index: index)
  end

  # ---- seed_all!(実カタログ) ----

  test "seed_all! は実カタログでも冪等(2回実行して件数が増えない)" do
    capture_io { SeedCatalog.seed_all! }
    counts = [ Genre.count, WordOrigin.count, PartOfSpeech.count, LinguisticFeature.count ]

    capture_io { SeedCatalog.seed_all! }

    assert_equal counts, [ Genre.count, WordOrigin.count, PartOfSpeech.count, LinguisticFeature.count ]
  end
end
