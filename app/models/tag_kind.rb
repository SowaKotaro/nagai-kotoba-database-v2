# タグ統括管理で扱う「種別」の目録(PORO)。URL の :kind パラメータからモデルを引くための
# ホワイトリストを兼ねる。ユーザー入力を constantize せず、この対応表にある種別だけを許可する。
class TagKind
  # 表示順。文字列キーは URL(/admin/tags/:kind)・i18n(admin.tags.kinds.*) の双方に使う。
  MODELS = {
    "genres" => Genre,
    "entity_types" => EntityType,
    "parts_of_speech" => PartOfSpeech,
    "word_origins" => WordOrigin,
    "linguistic_features" => LinguisticFeature
  }.freeze

  attr_reader :key

  def initialize(key)
    @key = key
  end

  # 表示順に並べた全種別。
  def self.all
    MODELS.keys.map { |key| new(key) }
  end

  # 未知の種別は 404 にする(任意のモデルを掴ませない安全策)。
  def self.find(key)
    raise ActiveRecord::RecordNotFound, "unknown tag kind: #{key.inspect}" unless MODELS.key?(key)

    new(key)
  end

  def model
    MODELS.fetch(key)
  end

  # ジャンルだけは階層(大→中→小)を持つ。表示・削除ガードの分岐に使う。
  def hierarchical?
    key == "genres"
  end

  # この画面からタグを新規追加できるか。
  # 言語学的特徴だけを許可する。他の種別はアノテーション・コンソールからその場追加できる
  # (ジャンルは親の選択が要る)ため、タグ管理では追加を受け付けない。
  def creatable?
    key == "linguistic_features"
  end

  # レコードが seed 管理(SeedCatalog 収載)か。「seed」印とリネーム時の警告表示に使う。
  # genre_index は id => Genre の索引(一覧での親参照の N+1 回避用)。
  def seeded?(record, genre_index: nil)
    SeedCatalog.seeded?(key, record, genre_index: genre_index)
  end

  # この種別に seed 管理のレコードが含まれうるか(一覧の注記表示に使う)。
  def seed_managed_kind?
    SeedCatalog.kind_seeded?(key)
  end

  def label
    I18n.t("admin.tags.kinds.#{key}")
  end

  def find_record(id)
    model.find(id)
  end

  # 一覧に出すレコード(表示順)。ジャンルは階層(木)を深さ優先でたどった順
  # (大 → その配下の中 → その配下の小 → 次の中 …)、他は名前順。
  def records
    hierarchical? ? ordered_genres : model.order(:name)
  end

  def total_count
    model.count
  end

  # id => 使用件数(このタグを付けている語義の数)のハッシュ。N+1 を避けるため一括集計する。
  def usage_counts
    case key
    when "entity_types"
      WordSense.where.not(entity_type_id: nil).group(:entity_type_id).count
    when "parts_of_speech"
      WordSense.where.not(part_of_speech_id: nil).group(:part_of_speech_id).count
    when "word_origins"
      WordSenseOrigin.group(:word_origin_id).count
    when "linguistic_features"
      WordSenseFeature.group(:linguistic_feature_id).distinct.count(:word_sense_id)
    when "genres"
      genre_usage_counts
    end
  end

  # 削除可能なレコード id の集合。未使用が条件。ジャンルは加えて子を持たないこと。
  # records/counts は呼び出し側で用意した値を渡す(再クエリを避ける)。
  def deletable_ids(records, counts)
    parent_ids = hierarchical? ? records.map(&:parent_id).compact.to_set : Set.new
    records.reject { |r| counts[r.id].to_i.positive? || parent_ids.include?(r.id) }
           .map(&:id)
           .to_set
  end

  private

  # ジャンルを階層(木)の深さ優先順に並べる。各階層内は名前順。
  # 全ジャンルを1クエリで取り、親→子の対応を作って根(大分類)からたどる。
  def ordered_genres
    by_parent = Genre.order(:name).group_by(&:parent_id)
    ordered = []
    append = lambda do |parent_id|
      (by_parent[parent_id] || []).each do |genre|
        ordered << genre
        append.call(genre.id)
      end
    end
    append.call(nil)
    ordered
  end

  # ジャンルの使用件数を階層で積み上げる。小分類に付く語義数を、自身とすべての祖先に加算する。
  def genre_usage_counts
    direct = WordSense.where.not(genre_id: nil).group(:genre_id).count
    parents = Genre.pluck(:id, :parent_id).to_h
    totals = Hash.new(0)
    direct.each do |genre_id, count|
      node = genre_id
      while node
        totals[node] += count
        node = parents[node]
      end
    end
    totals
  end
end
