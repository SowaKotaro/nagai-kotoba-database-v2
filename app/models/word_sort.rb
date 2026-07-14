# 単語一覧(絞り込み結果を含む)の並び順を表す値オブジェクト。
# キーはホワイトリストで管理し、未知の値は既定(登録が新しい順)へ畳む(生の SQL を外から掴ませない)。
# 読み系の並びは、語義が複数ある語でも決定的になるよう相関サブクエリで代表値へ集約する。
# 昇順は最小・降順は最大を代表にする(「読みが長い順」は最長の語義で並ぶ、が直感に合う)。
# ページ送りが安定するよう、どの並びも末尾を id で結ぶ。
class WordSort
  READING_MIN = "(SELECT MIN(word_senses.reading) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  READING_MAX = "(SELECT MAX(word_senses.reading) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  LENGTH_MIN = "(SELECT MIN(word_senses.reading_length) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  LENGTH_MAX = "(SELECT MAX(word_senses.reading_length) FROM word_senses WHERE word_senses.word_id = words.id)".freeze
  # 逆引き(末尾からの五十音順)。REVERSE は utf8mb4 でも文字単位で反転する。
  READING_REVERSED_MIN =
    "(SELECT MIN(REVERSE(word_senses.reading)) FROM word_senses WHERE word_senses.word_id = words.id)".freeze

  # キー → ORDER BY 句。定数リテラルのみで組む(shuffle だけは日替わりシードで動的に組む)。
  # 並びはセレクタの表示順を兼ねる。既定(登録が新しい順)を先頭に置く。
  ORDERS = {
    "created_desc" => Arel.sql("words.created_at DESC, words.id DESC"),
    "created_asc"  => Arel.sql("words.created_at ASC, words.id ASC"),
    "kana_asc"     => Arel.sql("#{READING_MIN} ASC, words.id ASC"),
    "kana_desc"    => Arel.sql("#{READING_MAX} DESC, words.id ASC"),
    "length_asc"   => Arel.sql("#{LENGTH_MIN} ASC, words.id ASC"),
    "length_desc"  => Arel.sql("#{LENGTH_MAX} DESC, words.id ASC"),
    "reverse_kana" => Arel.sql("#{READING_REVERSED_MIN} ASC, words.id ASC")
  }.freeze

  SHUFFLE_KEY = "shuffle"
  KEYS = (ORDERS.keys + [ SHUFFLE_KEY ]).freeze
  # ホームの「新着の単語 → すべて見る」から辿った一覧でも新着が先頭に来るよう、
  # 既定は登録が新しい順にする。
  DEFAULT_KEY = "created_desc"

  attr_reader :key

  def initialize(param)
    @key = KEYS.include?(param.to_s) ? param.to_s : DEFAULT_KEY
  end

  def default? = key == DEFAULT_KEY

  # Word の Relation に渡す ORDER BY。
  def order_clause
    key == SHUFFLE_KEY ? shuffle_clause : ORDERS.fetch(key)
  end

  private

  # 日替わりシャッフル。日付をシードにした決定的な擬似乱数順なので、
  # 同じ日のうちはページ送りしても順序が変わらず、日が変わると並び直る。
  def shuffle_clause
    seed = Date.current.strftime("%Y%m%d").to_i
    Arel.sql(ApplicationRecord.sanitize_sql_array([ "MD5(CONCAT(words.id, ?)) ASC, words.id ASC", seed ]))
  end
end
