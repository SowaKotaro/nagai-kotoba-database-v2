# words が持つ「語義の代表値」(一覧の並び替え・ランキングの指標)の再計算。
#
# 以前は WordSort が ORDER BY の中で相関サブクエリを評価していた:
#   ORDER BY (SELECT MAX(word_senses.reading_length) FROM word_senses
#             WHERE word_senses.word_id = words.id) DESC, words.id ASC
# これは LIMIT 100 でも公開語の全件でサブクエリが走ったうえ filesort まで通るため、
# インデックスが一切効かず語数に正比例して重くなっていた(17,600 語で 1 ページ 47〜88ms)。
# 代表値を words のカラムへ落として降順複合インデックスを張ったことで、
# ORDER BY が索引走査だけで解ける(同条件で 0.3〜1.1ms)。
#
# 値の出どころは word_senses と、その別表記・言語学的特徴。それらが変わったら
# 各モデルの after_commit がここを呼んで焼き直す。
#
# SQL 片はすべて定数の文字列リテラルで書き切る(WordSort と同じ方針)。外から来た値が
# 混ざらないことを静的解析でも追えるようにするため、絞り込みだけ sanitize_sql_array を通す。
class WordSenseMetrics
  # 小書きのかな(拗音・促音)。「文字数 - 拍数」では促音「ッ」と長音符が独立した1拍として
  # 数えられて現れないため、小書きの字を直接1字ずつ数える。
  SMALL_KANA = "ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ".freeze
  # 濁点・半濁点を持つかな。
  DAKUTEN_KANA =
    "ガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポヴ" \
    "がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽゔ".freeze
  # 長音符。
  CHOUON = "ー".freeze

  # 並び替え用の代表読み(min_reading など)の最大長。utf8mb4 で 255 字 = 1020 バイトなら
  # prefix ではない全長インデックスを張れる(prefix インデックスは ORDER BY に使えない)。
  # 収録基準では読みは最長でも数十字なので、実際に切り詰められることはまず無い。
  # 万一超えても、同じ 255 字で始まる語どうしの順序が id 順に落ちるだけで壊れない。
  READING_KEY_LIMIT = 255

  # 語義そのものから採る代表値。読みは COLLATE utf8mb4_bin へ落として数える
  # (格納時の as_ci のままだと小書き⇔並字・清濁が畳まれて数を取り違える)。
  SENSE_METRICS_SQL = <<~SQL.freeze
    SELECT word_senses.word_id AS word_id,
           COUNT(*)                                     AS sense_count,
           MIN(word_senses.reading_length)              AS min_reading_length,
           MAX(word_senses.reading_length)              AS max_reading_length,
           MAX(word_senses.mora_count)                  AS max_mora_count,
           MIN(word_senses.ring_crossing_count)         AS min_ring_crossing_count,
           MAX(word_senses.ring_crossing_count)         AS max_ring_crossing_count,
           LEFT(MIN(word_senses.reading), #{READING_KEY_LIMIT})          AS min_reading,
           LEFT(MAX(word_senses.reading), #{READING_KEY_LIMIT})          AS max_reading,
           LEFT(MIN(REVERSE(word_senses.reading)), #{READING_KEY_LIMIT}) AS min_reversed_reading,
           MAX(CHAR_LENGTH(word_senses.reading) - CHAR_LENGTH(REGEXP_REPLACE(
             word_senses.reading COLLATE utf8mb4_bin, '[#{SMALL_KANA}]', ''))) AS max_small_kana_count,
           MAX(CHAR_LENGTH(word_senses.reading) - CHAR_LENGTH(REPLACE(
             word_senses.reading COLLATE utf8mb4_bin, '#{CHOUON}', '')))       AS max_chouon_count,
           MAX(CHAR_LENGTH(word_senses.reading) - CHAR_LENGTH(REGEXP_REPLACE(
             word_senses.reading COLLATE utf8mb4_bin, '[#{DAKUTEN_KANA}]', ''))) AS max_dakuten_count
    FROM word_senses
    %<sense_filter>s
    GROUP BY word_senses.word_id
  SQL

  VARIANT_METRICS_SQL = <<~SQL.freeze
    SELECT word_senses.word_id AS word_id, COUNT(*) AS variant_count
    FROM word_sense_variants
    INNER JOIN word_senses ON word_senses.id = word_sense_variants.word_sense_id
    %<sense_filter>s
    GROUP BY word_senses.word_id
  SQL

  FEATURE_METRICS_SQL = <<~SQL.freeze
    SELECT word_senses.word_id AS word_id, COUNT(*) AS feature_count
    FROM word_sense_features
    INNER JOIN word_senses ON word_senses.id = word_sense_features.word_sense_id
    %<sense_filter>s
    GROUP BY word_senses.word_id
  SQL

  # 語義が1つも無い語は各集計が NULL になる。件数系は 0 に畳み、指標系は NULL のままにする
  # (0 と「該当なし」を区別したいため。ランキングは下限で NULL を落とす)。
  # updated_at は意図的に更新しない: 代表値は表示内容を変えないので、ここで進めてしまうと
  # 詳細ページの ETag と llms-full.txt のキャッシュが無意味に失効する。
  UPDATE_SQL = <<~SQL.freeze
    UPDATE words
    LEFT JOIN (%<sense_metrics>s) AS sense_metrics   ON sense_metrics.word_id   = words.id
    LEFT JOIN (%<variant_metrics>s) AS variant_metrics ON variant_metrics.word_id = words.id
    LEFT JOIN (%<feature_metrics>s) AS feature_metrics ON feature_metrics.word_id = words.id
    SET words.sense_count             = COALESCE(sense_metrics.sense_count, 0),
        words.variant_count           = COALESCE(variant_metrics.variant_count, 0),
        words.feature_count           = COALESCE(feature_metrics.feature_count, 0),
        words.min_reading_length      = sense_metrics.min_reading_length,
        words.max_reading_length      = sense_metrics.max_reading_length,
        words.max_mora_count          = sense_metrics.max_mora_count,
        words.max_small_kana_count    = sense_metrics.max_small_kana_count,
        words.max_chouon_count        = sense_metrics.max_chouon_count,
        words.max_dakuten_count       = sense_metrics.max_dakuten_count,
        words.min_ring_crossing_count = sense_metrics.min_ring_crossing_count,
        words.max_ring_crossing_count = sense_metrics.max_ring_crossing_count,
        words.min_reading             = sense_metrics.min_reading,
        words.max_reading             = sense_metrics.max_reading,
        words.min_reversed_reading    = sense_metrics.min_reversed_reading
    %<word_filter>s
  SQL

  class << self
    # 指定した語(省略時は全件)の代表値を焼き直す。1文の UPDATE で完結する。
    def refresh!(word_ids = :all)
      ids = word_ids == :all ? nil : Array(word_ids).compact.uniq
      return if ids && ids.empty?

      ApplicationRecord.connection.execute(update_sql(ids))
    end

    # 実行される UPDATE 文(テストと backfill から参照する)。
    def update_sql(ids)
      # 1語の焼き直しでも派生表を全件 GROUP BY しないよう、内側にも同じ絞り込みを掛ける。
      sense_filter = ids ? sanitize("WHERE word_senses.word_id IN (?)", ids) : ""
      word_filter  = ids ? sanitize("WHERE words.id IN (?)", ids) : ""

      format(
        UPDATE_SQL,
        sense_metrics: format(SENSE_METRICS_SQL, sense_filter: sense_filter),
        variant_metrics: format(VARIANT_METRICS_SQL, sense_filter: sense_filter),
        feature_metrics: format(FEATURE_METRICS_SQL, sense_filter: sense_filter),
        word_filter: word_filter
      )
    end

    private

    def sanitize(condition, ids)
      ApplicationRecord.sanitize_sql_array([ condition, ids ])
    end
  end
end
