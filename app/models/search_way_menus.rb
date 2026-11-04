# ホームの探し方の入口(docs/design.md §5.2)のうち、押すとその場で選択肢が開くボタンの中身。
# 選択肢はどれも単語一覧(/words)の絞り込みの値で、公開語義の無いものは出さない(選んでも空の一覧になる。/genres と同じ)。
# 件数は索引と同じ PublishedSenseCounts のキャッシュから引き、ここではマスタと突き合わせて選び、並べるだけにする。
# ホームは毎リクエスト読むので、組んだ選択肢ごと 1 時間置く(組み直すとマスタを引く SQL が 5 本走る)。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class SearchWayMenus
  # 開くボタンの並び(左から)。キーはボタンの語(HomeHelper#home_search_ways)と、選択肢を返すメソッドの名前を兼ねる
  KEYS = %i[genre entity_type linguistic_feature reading_length word_origin part_of_speech].freeze
  # エンティティは 60 種を超えるので、語の多い順に上から出す(全部は /entity_types が並べる)
  ENTITY_TYPE_LIMIT = 20
  # 読みの長さの区切り。19 文字までは 1 文字ずつ、語の少ない 20 文字以上はまとめる(2026-11-03 オーナー指示。分布は統計 §3)
  READING_LENGTH_BANDS = [ *(WordSense::MIN_READING_LENGTH..19).map { |length| length..length }, 20.. ].freeze
  # 件数(PublishedSenseCounts)と同じく 1 時間で組み直す。形を変えたら版を上げる
  CACHE_KEY = "search_way_menus/v1".freeze
  CACHE_TTL = 1.hour
  RACE_CONDITION_TTL = 30.seconds

  # name は選択肢の名前(マスタの名前。読みの長さだけは区切りの Range で、語はビューが組む)、params は /words の絞り込み
  Option = Struct.new(:name, :params)

  # { genre: [Option, ...], ... }(KEYS の順。公開語義のある選択肢が 1 つも無いキーは空の配列)
  def self.all
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL, race_condition_ttl: RACE_CONDITION_TTL) do
      menus = new
      KEYS.index_with { |key| menus.send(key) }
    end
  end

  private

  # 大分類(登録順)。語義に付くのは小分類なので、公開語義のある小分類から親を 2 段辿る(Genre::LEVELS)
  def genre
    small_ids = PublishedSenseCounts.by_genre.keys.compact
    medium_ids = Genre.where(id: small_ids).select(:parent_id)
    Genre.where(id: Genre.where(id: medium_ids).select(:parent_id)).order(:id)
         .map { |genre| Option.new(genre.name, { genre_id: genre.id }) }
  end

  def entity_type
    EntityType.ordered_by_published_count(PublishedSenseCounts.by_entity_type).first(ENTITY_TYPE_LIMIT)
              .map { |entity_type| Option.new(entity_type.name, { entity_type_id: entity_type.id }) }
  end

  # 用語解説の順(似た特徴が隣り合う。/linguistic_features と同じ並び)
  def linguistic_feature
    LinguisticFeature.where(id: PublishedSenseCounts.by_linguistic_feature.keys).in_glossary_order
                     .map { |feature| Option.new(feature.name, { linguistic_feature_id: feature.id }) }
  end

  def reading_length
    lengths = PublishedSenseCounts.by_reading_length.keys.compact
    READING_LENGTH_BANDS.select { |band| lengths.any? { |length| band.cover?(length) } }
                        .map { |band| Option.new(band, reading_length_params(band)) }
  end

  # 語の多い順(同数は登録順)。日本語・英語のあとに、語の少ない言語が続く
  def word_origin
    counts = PublishedSenseCounts.by_word_origin
    WordOrigin.where(id: counts.keys).sort_by { |origin| [ -counts[origin.id], origin.id ] }
              .map { |origin| Option.new(origin.name, { word_origin_id: origin.id }) }
  end

  # 登録順(普通名詞 → 固有名詞 → …)。4 つしかないので数では並べ替えない
  def part_of_speech
    PartOfSpeech.where(id: PublishedSenseCounts.by_part_of_speech.keys.compact).order(:id)
                .map { |part_of_speech| Option.new(part_of_speech.name, { part_of_speech_id: part_of_speech.id }) }
  end

  # 1 文字の区切りはちょうどの値、上限の無い区切り(20 文字以上)は下限だけで絞る
  def reading_length_params(band)
    band.end ? { reading_length: band.begin } : { reading_length_min: band.begin }
  end
end
