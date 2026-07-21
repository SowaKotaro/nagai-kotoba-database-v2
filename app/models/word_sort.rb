# 単語一覧(絞り込み結果を含む)の並び順を表す値オブジェクト。
# キーはホワイトリストで管理し、未知の値は既定(登録が新しい順)へ畳む(生の SQL を外から掴ませない)。
# 読み系の並びは、語義が複数ある語でも決定的になるよう相関サブクエリで代表値へ集約する。
# 昇順は最小・降順は最大を代表にする(「読みが長い順」は最長の語義で並ぶ、が直感に合う)。
# ページ送りが安定するよう、どの並びも末尾を id で結ぶ。
#
# 並びは2群ある。
#   - 基本の並び(BASE_ORDERS): 登録順・五十音順など、一覧を眺めるための順序。
#   - ランキングの並び(RANKING_ORDERS): 「◯◯が多い順」。ランキングページ(WordRanking)と共有し、
#     各ランキングの「もっと見る」は同じキーの一覧へ遷移する。
#
# SQL 片はすべて定数の文字列リテラルで書き切る(メソッドやブロックで組み立てない)。
# 外部入力が混ざらないことを静的解析でも追えるようにするため、重複を承知で並べている。
class WordSort
  # --- 基本の並びで使う代表値 ---
  READING_MIN = "(SELECT MIN(word_senses.reading) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  READING_MAX = "(SELECT MAX(word_senses.reading) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  LENGTH_MIN =
    "(SELECT MIN(word_senses.reading_length) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 逆引き(末尾からの五十音順)。REVERSE は utf8mb4 でも文字単位で反転する。
  READING_REVERSED_MIN =
    "(SELECT MIN(REVERSE(word_senses.reading)) FROM word_senses WHERE word_senses.word_id = words.id)".freeze

  # --- ランキングの指標(既定は「値が大きいほど上位」。少ない順のランキングだけ例外的に昇順) ---
  # 読みの文字数。このサイトの看板。
  LENGTH_MAX =
    "(SELECT MAX(word_senses.reading_length) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 拍(モーラ)の数。拗音を1拍と数えるため、文字数とは順位がずれる。
  MORA_MAX =
    "(SELECT MAX(word_senses.mora_count) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 表記(表層形)の文字数。読みではなく字面の長さ。
  SURFACE_LENGTH = "CHAR_LENGTH(words.surface)".freeze
  # 1字あたりの読みの長さ。字面が短いのに読みが長い「字の重い語」が上位に来る。
  READING_DENSITY =
    "((SELECT MAX(word_senses.reading_length) FROM word_senses WHERE word_senses.word_id = words.id) " \
    "/ NULLIF(CHAR_LENGTH(words.surface), 0))".freeze
  # 小書きのかな(拗音・促音)の数。促音「ッ」と長音符は独立した1拍として数えられ、
  # 「文字数 - 拍数」では促音が現れないため、小書きのかなを直接1文字ずつ数える。
  # 濁点の数(下)と同じく、as_ci のままだと小書き⇔並字(ッ=ツ・ャ=ヤ)が畳まれかねないので
  # utf8mb4_bin へ落として、列挙した小書きの字だけを厳密に数える。
  SMALL_KANA =
    "ぁぃぅぇぉっゃゅょゎゕゖ" \
    "ァィゥェォッャュョヮヵヶ".freeze
  SMALL_KANA_MAX =
    "(SELECT MAX(CHAR_LENGTH(word_senses.reading) - CHAR_LENGTH(REGEXP_REPLACE(" \
    "word_senses.reading COLLATE utf8mb4_bin, '[#{SMALL_KANA}]', ''))) " \
    "FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 長音符「ー」の数。
  # 濁点の数(下)と同じく、数えるときは必ず utf8mb4_bin へ落として清濁・かなの異同を潰さない。
  CHOUON_MAX =
    "(SELECT MAX(CHAR_LENGTH(word_senses.reading) - " \
    "CHAR_LENGTH(REPLACE(word_senses.reading COLLATE utf8mb4_bin, 'ー', ''))) " \
    "FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 濁点・半濁点の数。REGEXP の照合は列の照合順序に従うため、
  # 読み(as_ci)のままだと「カ=ガ」と畳まれて数えられない。
  DAKUTEN_MAX =
    "(SELECT MAX(CHAR_LENGTH(word_senses.reading) - CHAR_LENGTH(REGEXP_REPLACE(" \
    "word_senses.reading COLLATE utf8mb4_bin, " \
    "'[ガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポヴがぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽゔ]', ''))) " \
    "FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 円環交差数(五十音円環で読みを結んだ折れ線の交差回数)。多い順と少ない順の両方でランキングにするため、
  # 降順は最大・昇順は最小を代表値にする。
  RING_CROSSING_MAX =
    "(SELECT MAX(word_senses.ring_crossing_count) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  RING_CROSSING_MIN =
    "(SELECT MIN(word_senses.ring_crossing_count) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 語義(同音異義・多義)の数。
  SENSE_COUNT = "(SELECT COUNT(*) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 別表記の数。
  VARIANT_COUNT =
    "(SELECT COUNT(*) FROM word_sense_variants " \
    "JOIN word_senses ON word_senses.id = word_sense_variants.word_sense_id " \
    "WHERE word_senses.word_id = words.id)".freeze
  # 言語学的特徴の付与数。
  FEATURE_COUNT =
    "(SELECT COUNT(*) FROM word_sense_features " \
    "JOIN word_senses ON word_senses.id = word_sense_features.word_sense_id " \
    "WHERE word_senses.word_id = words.id)".freeze

  # 基本の並び。並びはセレクタの表示順を兼ね、既定を先頭に置く。
  BASE_ORDERS = {
    "created_desc" => Arel.sql("words.created_at DESC, words.id DESC"),
    "created_asc"  => Arel.sql("words.created_at ASC, words.id ASC"),
    "kana_asc"     => Arel.sql("#{READING_MIN} ASC, words.id ASC"),
    "kana_desc"    => Arel.sql("#{READING_MAX} DESC, words.id ASC"),
    "length_asc"   => Arel.sql("#{LENGTH_MIN} ASC, words.id ASC"),
    "reverse_kana" => Arel.sql("#{READING_REVERSED_MIN} ASC, words.id ASC")
  }.freeze

  # ランキングの並び。指標の降順 + id で同値の順序を固定する。
  RANKING_ORDERS = {
    "length_desc"          => Arel.sql("#{LENGTH_MAX} DESC, words.id ASC"),
    "mora_desc"            => Arel.sql("#{MORA_MAX} DESC, words.id ASC"),
    "surface_length_desc"  => Arel.sql("#{SURFACE_LENGTH} DESC, words.id ASC"),
    "reading_density_desc" => Arel.sql("#{READING_DENSITY} DESC, words.id ASC"),
    "small_kana_desc"      => Arel.sql("#{SMALL_KANA_MAX} DESC, words.id ASC"),
    "chouon_desc"          => Arel.sql("#{CHOUON_MAX} DESC, words.id ASC"),
    "dakuten_desc"         => Arel.sql("#{DAKUTEN_MAX} DESC, words.id ASC"),
    "ring_crossing_desc"   => Arel.sql("#{RING_CROSSING_MAX} DESC, words.id ASC"),
    # 少ない順は 0 回の語が大量に並ぶため、同値のときは読みが長い語を上位にする
    # (「読みが長いのに交差しない」語が頭に来て、順位表として意味が出る)。
    "ring_crossing_asc"    => Arel.sql("#{RING_CROSSING_MIN} ASC, #{LENGTH_MAX} DESC, words.id ASC"),
    "sense_count_desc"     => Arel.sql("#{SENSE_COUNT} DESC, words.id ASC"),
    "variant_count_desc"   => Arel.sql("#{VARIANT_COUNT} DESC, words.id ASC"),
    "feature_count_desc"   => Arel.sql("#{FEATURE_COUNT} DESC, words.id ASC")
  }.freeze

  # ランキングページ用の SELECT。順位の根拠になる値を ranking_metric として持ち帰り、
  # 絞り込み(下限)はその別名への HAVING で行う(WordRanking)。
  RANKING_SELECTS = {
    "length_desc"          => Arel.sql("words.*, #{LENGTH_MAX} AS ranking_metric"),
    "mora_desc"            => Arel.sql("words.*, #{MORA_MAX} AS ranking_metric"),
    "surface_length_desc"  => Arel.sql("words.*, #{SURFACE_LENGTH} AS ranking_metric"),
    "reading_density_desc" => Arel.sql("words.*, #{READING_DENSITY} AS ranking_metric"),
    "small_kana_desc"      => Arel.sql("words.*, #{SMALL_KANA_MAX} AS ranking_metric"),
    "chouon_desc"          => Arel.sql("words.*, #{CHOUON_MAX} AS ranking_metric"),
    "dakuten_desc"         => Arel.sql("words.*, #{DAKUTEN_MAX} AS ranking_metric"),
    "ring_crossing_desc"   => Arel.sql("words.*, #{RING_CROSSING_MAX} AS ranking_metric"),
    "ring_crossing_asc"    => Arel.sql("words.*, #{RING_CROSSING_MIN} AS ranking_metric"),
    "sense_count_desc"     => Arel.sql("words.*, #{SENSE_COUNT} AS ranking_metric"),
    "variant_count_desc"   => Arel.sql("words.*, #{VARIANT_COUNT} AS ranking_metric"),
    "feature_count_desc"   => Arel.sql("words.*, #{FEATURE_COUNT} AS ranking_metric")
  }.freeze

  ORDERS = BASE_ORDERS.merge(RANKING_ORDERS).freeze

  SHUFFLE_KEY = "shuffle"
  RANKING_KEYS = RANKING_ORDERS.keys.freeze

  # 並び順セレクタに出すキーと、その表示順。
  # 「登録順 → 五十音 → 読みの長さ → その他のランキング」と、粗い順から細かい観点へ並べる。
  # シャッフルは並び順ではなく「引き直す」操作なので、セレクタには出さず一覧のボタンから使う。
  SELECTABLE_KEYS = %w[
    created_desc created_asc
    kana_asc kana_desc reverse_kana
    length_desc length_asc
    mora_desc surface_length_desc reading_density_desc
    small_kana_desc chouon_desc dakuten_desc
    ring_crossing_desc ring_crossing_asc
    sense_count_desc variant_count_desc feature_count_desc
  ].freeze

  KEYS = (SELECTABLE_KEYS + [ SHUFFLE_KEY ]).freeze
  # ホームの「新着の単語 → すべて見る」から辿った一覧でも新着が先頭に来るよう、
  # 既定は登録が新しい順にする。
  DEFAULT_KEY = "created_desc"
  # シャッフルのシード。URL から受けるので長さだけ抑える(SQL へはプレースホルダで渡す)。
  SEED_LIMIT = 16

  attr_reader :key

  # seed はシャッフル専用。指定が無ければ日付をシードにして、その日のうちは順序を固定する。
  def initialize(param, seed: nil)
    @key = KEYS.include?(param.to_s) ? param.to_s : DEFAULT_KEY
    @seed = seed.to_s.presence&.slice(0, SEED_LIMIT)
  end

  def default? = key == DEFAULT_KEY
  def shuffle? = key == SHUFFLE_KEY

  # Word の Relation に渡す ORDER BY。
  def order_clause
    shuffle? ? shuffle_clause : ORDERS.fetch(key)
  end

  private

  # シードから決まる擬似乱数順。同じシードのうちはページ送りしても順序が変わらない。
  # シード無し(日付シード)なら1日で並び直り、「シャッフルする」ボタンから来たときは
  # その都度新しいシードが振られるので、押すたびに引き直せる。
  def shuffle_clause
    seed = @seed || Date.current.strftime("%Y%m%d")
    Arel.sql(ApplicationRecord.sanitize_sql_array([ "MD5(CONCAT(words.id, ?)) ASC, words.id ASC", seed ]))
  end
end
