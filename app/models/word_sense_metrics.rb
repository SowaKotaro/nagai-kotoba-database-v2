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
# 種別: 書き込み処理。
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
  # (照合順序の同一視に数え方を左右させないための備え。実測と理由は docs/data-model.md §5)。
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

  # words の代表値の列と、その値を求める式。UPDATE の SET と、backfill:verify の突き合わせ(mismatches)が
  # この 1 つの表を共有する(代表値の列を足すときはここと、上の集計 SQL に足す)。
  # 語義が1つも無い語は各集計が NULL になる。件数系は 0 に畳み、指標系は NULL のままにする
  # (0 と「該当なし」を区別したいため。ランキングは下限で NULL を落とす)。
  COLUMN_EXPRESSIONS = {
    "sense_count"             => "COALESCE(sense_metrics.sense_count, 0)",
    "variant_count"           => "COALESCE(variant_metrics.variant_count, 0)",
    "feature_count"           => "COALESCE(feature_metrics.feature_count, 0)",
    "min_reading_length"      => "sense_metrics.min_reading_length",
    "max_reading_length"      => "sense_metrics.max_reading_length",
    "max_mora_count"          => "sense_metrics.max_mora_count",
    "max_small_kana_count"    => "sense_metrics.max_small_kana_count",
    "max_chouon_count"        => "sense_metrics.max_chouon_count",
    "max_dakuten_count"       => "sense_metrics.max_dakuten_count",
    "min_ring_crossing_count" => "sense_metrics.min_ring_crossing_count",
    "max_ring_crossing_count" => "sense_metrics.max_ring_crossing_count",
    "min_reading"             => "sense_metrics.min_reading",
    "max_reading"             => "sense_metrics.max_reading",
    "min_reversed_reading"    => "sense_metrics.min_reversed_reading"
  }.freeze

  METRICS_JOINS = <<~SQL.freeze
    LEFT JOIN (%<sense_metrics>s) AS sense_metrics   ON sense_metrics.word_id   = words.id
    LEFT JOIN (%<variant_metrics>s) AS variant_metrics ON variant_metrics.word_id = words.id
    LEFT JOIN (%<feature_metrics>s) AS feature_metrics ON feature_metrics.word_id = words.id
  SQL

  # UPDATE の SET 句(COLUMN_EXPRESSIONS から組む)。
  SET_CLAUSE = COLUMN_EXPRESSIONS.map { |column, expression| "words.#{column} = #{expression}" }.join(",\n").freeze

  # updated_at は意図的に更新しない: 代表値は表示内容を変えないので、ここで進めてしまうと
  # 詳細ページの ETag と llms-full.txt のキャッシュが無意味に失効する。
  UPDATE_SQL = <<~SQL.freeze
    UPDATE words
    #{METRICS_JOINS}SET #{SET_CLAUSE}
    %<word_filter>s
  SQL

  # 代表値が集計と食い違う語を探す SELECT(backfill:verify 用。読み取りだけ)。列ごとに、いまの値・あるべき値・
  # 食い違うかを返す。比べるのは NULL を等しいとみなす <=> で、文字列の列はカラムの照合順序(as_ci)で比べる
  # (並び替えの結果が変わらない違い、たとえばひらがなとカタカナの違いは不整合としない)。
  MISMATCH_COLUMNS = COLUMN_EXPRESSIONS.map do |column, expression|
    "words.#{column} AS actual_#{column}, #{expression} AS expected_#{column}, " \
      "NOT (words.#{column} <=> #{expression}) AS #{column}_differs"
  end.join(",\n").freeze
  MISMATCH_CONDITION = COLUMN_EXPRESSIONS.map { |column, expression| "NOT (words.#{column} <=> #{expression})" }
                                         .join("\nOR ").freeze
  MISMATCH_SQL = <<~SQL.freeze
    SELECT words.id AS word_id,
    #{MISMATCH_COLUMNS}
    FROM words
    #{METRICS_JOINS}WHERE #{MISMATCH_CONDITION}
    ORDER BY words.id
  SQL

  class << self
    # 指定した語(省略時は全件)の代表値を焼き直す。1文の UPDATE で完結する。
    def refresh!(word_ids = :all)
      ids = word_ids == :all ? nil : Array(word_ids).compact.uniq
      return if ids && ids.empty?

      ApplicationRecord.connection.execute(update_sql(ids))
    end

    # 代表値が語義側の集計と食い違う語と列(backfill:verify が使う。読み取りだけで、何も直さない)。
    # [{ word_id:, column:, actual:, expected: }, ...]
    def mismatches
      sql = format(MISMATCH_SQL, **metrics_subqueries(""))
      ApplicationRecord.connection.select_all(sql).flat_map do |row|
        COLUMN_EXPRESSIONS.keys.filter_map do |column|
          next unless row["#{column}_differs"].to_i == 1

          { word_id: row["word_id"], column: column, actual: row["actual_#{column}"], expected: row["expected_#{column}"] }
        end
      end
    end

    # 実行される UPDATE 文(refresh! から呼ぶ)。
    def update_sql(ids)
      # 1語の焼き直しでも派生表を全件 GROUP BY しないよう、内側にも同じ絞り込みを掛ける。
      sense_filter = ids ? sanitize("WHERE word_senses.word_id IN (?)", ids) : ""
      word_filter  = ids ? sanitize("WHERE words.id IN (?)", ids) : ""

      format(UPDATE_SQL, **metrics_subqueries(sense_filter), word_filter: word_filter)
    end

    private

    def metrics_subqueries(sense_filter)
      {
        sense_metrics: format(SENSE_METRICS_SQL, sense_filter: sense_filter),
        variant_metrics: format(VARIANT_METRICS_SQL, sense_filter: sense_filter),
        feature_metrics: format(FEATURE_METRICS_SQL, sense_filter: sense_filter)
      }
    end

    def sanitize(condition, ids)
      ApplicationRecord.sanitize_sql_array([ condition, ids ])
    end
  end
end
