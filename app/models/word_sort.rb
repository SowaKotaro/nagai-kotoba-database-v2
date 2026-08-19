# 単語一覧(絞り込み結果を含む)の並び順を表す値オブジェクト。
# キーはホワイトリストで管理し、未知の値は既定(登録が新しい順)へ畳む(生の SQL を外から掴ませない)。
# ページ送りが安定するよう、どの並びも末尾を id で結ぶ。
#
# 並びは2群ある。
#   - 基本の並び(BASE_ORDERS): 登録順・五十音順など、一覧を眺めるための順序。
#   - ランキングの並び(RANKING_ORDERS): 「◯◯が多い順」。ランキングページ(WordRanking)と共有し、
#     各ランキングの「もっと見る」は同じキーの一覧へ遷移する。
#
# 並びの指標はすべて words のカラムで、AddSenseMetricsToWords で「指標 + id」の複合インデックスが
# 張ってある(降順の指標には降順インデックス)。かつては ORDER BY の中で語義への相関サブクエリを
# 評価していたが、LIMIT に関わらず公開語の全件でサブクエリが走ったうえ filesort まで通るため、
# 語数に正比例して重くなっていた。カラム化で ORDER BY ... LIMIT が索引走査だけで解ける。
# 代表値(最小/最大)の焼き直しは WordSenseMetrics が担う。
#
# SQL 片はすべて定数の文字列リテラルで書き切る(メソッドやブロックで組み立てない)。
# 外部入力が混ざらないことを静的解析でも追えるようにするため、重複を承知で並べている。
class WordSort
  # 基本の並び。並びはセレクタの表示順を兼ね、既定を先頭に置く。
  # created_desc / created_asc は annotated_at(注釈完了 = 公開した日時)で並べる。created_at は
  # 一括登録で下書きを作った日時でしかなく、公開した順とは何日もずれるため、公開面の「収録順」
  # には使わない。キー名は既に URL(?sort=created_desc)として世に出ているので変えない。
  # 昇順は最小・降順は最大を代表にする(「読みが長い順」は最長の語義で並ぶ、が直感に合う)。
  BASE_ORDERS = {
    "created_desc" => Arel.sql("words.annotated_at DESC, words.id DESC"),
    "created_asc"  => Arel.sql("words.annotated_at ASC, words.id ASC"),
    "kana_asc"     => Arel.sql("words.min_reading ASC, words.id ASC"),
    "kana_desc"    => Arel.sql("words.max_reading DESC, words.id ASC"),
    "length_asc"   => Arel.sql("words.min_reading_length ASC, words.id ASC"),
    # 逆引き(末尾からの五十音順)。読みを反転した代表値で並べる。
    "reverse_kana" => Arel.sql("words.min_reversed_reading ASC, words.id ASC")
  }.freeze

  # ランキングの並び。指標の降順 + id で同値の順序を固定する。
  RANKING_ORDERS = {
    "length_desc"          => Arel.sql("words.max_reading_length DESC, words.id ASC"),
    "mora_desc"            => Arel.sql("words.max_mora_count DESC, words.id ASC"),
    "surface_length_desc"  => Arel.sql("words.surface_length DESC, words.id ASC"),
    "reading_density_desc" => Arel.sql("words.reading_density DESC, words.id ASC"),
    "small_kana_desc"      => Arel.sql("words.max_small_kana_count DESC, words.id ASC"),
    "chouon_desc"          => Arel.sql("words.max_chouon_count DESC, words.id ASC"),
    "dakuten_desc"         => Arel.sql("words.max_dakuten_count DESC, words.id ASC"),
    "ring_crossing_desc"   => Arel.sql("words.max_ring_crossing_count DESC, words.id ASC"),
    # 少ない順は 0 回の語が大量に並ぶため、同値のときは読みが長い語を上位にする
    # (「読みが長いのに交差しない」語が頭に来て、順位表として意味が出る)。
    "ring_crossing_asc"    => Arel.sql("words.min_ring_crossing_count ASC, words.max_reading_length DESC, words.id ASC"),
    "sense_count_desc"     => Arel.sql("words.sense_count DESC, words.id ASC"),
    "variant_count_desc"   => Arel.sql("words.variant_count DESC, words.id ASC"),
    "feature_count_desc"   => Arel.sql("words.feature_count DESC, words.id ASC")
  }.freeze

  # 各ランキングの指標が入っている words のカラム。ランキングページ(WordRanking)が
  # 順位の値の取り出しと下限の絞り込みに使う。ORDER BY の先頭カラムと必ず一致させること。
  RANKING_METRICS = {
    "length_desc"          => :max_reading_length,
    "mora_desc"            => :max_mora_count,
    "surface_length_desc"  => :surface_length,
    "reading_density_desc" => :reading_density,
    "small_kana_desc"      => :max_small_kana_count,
    "chouon_desc"          => :max_chouon_count,
    "dakuten_desc"         => :max_dakuten_count,
    "ring_crossing_desc"   => :max_ring_crossing_count,
    "ring_crossing_asc"    => :min_ring_crossing_count,
    "sense_count_desc"     => :sense_count,
    "variant_count_desc"   => :variant_count,
    "feature_count_desc"   => :feature_count
  }.freeze

  ORDERS = BASE_ORDERS.merge(RANKING_ORDERS).freeze

  SHUFFLE_KEY = "shuffle"
  RANKING_KEYS = RANKING_ORDERS.keys.freeze

  # 並び順セレクタに出すキーと、その表示順。
  # 「収録順 → 五十音 → 読みの長さ → その他のランキング」と、粗い順から細かい観点へ並べる。
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
  # 既定は収録(公開)が新しい順にする。
  DEFAULT_KEY = "created_desc"
  # シャッフルのシード。URL から受けるので長さだけ抑える(SQL へはプレースホルダで渡す)。
  SEED_LIMIT = 16

  attr_reader :key

  # seed はシャッフル専用。URL に無ければリクエストごとに新しく振る(開くたびに引き直す)。
  #
  # かつては「シャッフルする」リンクの href 側で毎回シードを振っていたが、それだと
  # 一覧を描画するたびに未知の URL が生まれ、クローラが辿った先でもまた新しい URL が
  # 生まれる無限ループになっていた(2026-08 の Search Console で「noindex により除外」が
  # 3,186 件まで単調増加した原因。本物のページのクロールが後回しにされていた)。
  # href は seed 無しの1本に固定し、シードはサーバ側だけで持つ。
  def initialize(param, seed: nil)
    @key = KEYS.include?(param.to_s) ? param.to_s : DEFAULT_KEY
    @seed = (seed.to_s.presence&.slice(0, SEED_LIMIT) || SecureRandom.hex(4)) if shuffle?
  end

  # 実際に使ったシャッフルのシード。ページ送りが引き継いで並びを保つ。シャッフル以外は nil。
  attr_reader :seed

  def default? = key == DEFAULT_KEY
  def shuffle? = key == SHUFFLE_KEY

  # Word の Relation に渡す ORDER BY。
  def order_clause
    shuffle? ? shuffle_clause : ORDERS.fetch(key)
  end

  private

  # シードから決まる擬似乱数順。同じシードのうちはページ送りしても順序が変わらない。
  # シードは初期化時に必ず決まる(URL 指定が無ければ新規に振る)ので、
  # 「シャッフルする」を押すたび・開き直すたびに並びが引き直される。
  def shuffle_clause
    Arel.sql(ApplicationRecord.sanitize_sql_array([ "MD5(CONCAT(words.id, ?)) ASC, words.id ASC", @seed ]))
  end
end
