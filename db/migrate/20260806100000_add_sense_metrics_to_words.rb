class AddSenseMetricsToWords < ActiveRecord::Migration[8.1]
  # 一覧の並び替え(WordSort)とランキング(WordRanking)の指標を words のカラムへ落とす。
  #
  # これまでは ORDER BY の中で相関サブクエリ(SELECT MAX(...) FROM word_senses WHERE
  # word_id = words.id)を評価していた。LIMIT 100 でも公開語の全件でサブクエリが走り、
  # そのうえ filesort まで通るためインデックスが効かず、語数に正比例して重くなっていた。
  # 代表値をカラム化して「指標 DESC + id ASC」の降順複合インデックスを張ると、
  # ORDER BY ... LIMIT が索引走査だけで解ける(実測 17,600 語で 47〜88ms → 0.3〜1.1ms)。
  #
  # 引き換えに words への書き込みでインデックス16本の保守が増えるが、
  # words は1万件規模・書き込みは登録とアノテーションだけなので許容する。
  #
  # 代表値の再計算は WordSenseMetrics が持ち、word_senses / 別表記 / 特徴の
  # after_commit から呼ばれる。既存行はこのマイグレーションの中で埋め切る
  # (rake の backfill 待ちにすると、デプロイ直後のランキングが空になるため)。

  # 件数系のカラム。語義が1つも無い語も「0件」と言い切れるので NOT NULL(既定 0)にする。
  # [名前, コメント]
  COUNT_COLUMNS = [
    [ :sense_count, "語義の数(sense_count_desc)" ],
    [ :variant_count, "別表記の数(variant_count_desc)" ],
    [ :feature_count, "言語学的特徴の付与数(feature_count_desc)" ]
  ].freeze

  # 指標系のカラム。語義が無ければ「該当なし」なので NULL 許容にする
  # (0 と区別したい。ランキングは範囲条件で NULL を落とす)。[名前, 型, コメント]
  METRIC_COLUMNS = [
    [ :min_reading_length, :integer, "読みの文字数の最小(length_asc)" ],
    [ :max_reading_length, :integer, "読みの文字数の最大(length_desc)" ],
    [ :max_mora_count, :integer, "モーラ数の最大(mora_desc)" ],
    [ :max_small_kana_count, :integer, "小書きのかなの数の最大(small_kana_desc)" ],
    [ :max_chouon_count, :integer, "長音符の数の最大(chouon_desc)" ],
    [ :max_dakuten_count, :integer, "濁点・半濁点の数の最大(dakuten_desc)" ],
    [ :min_ring_crossing_count, :integer, "円環交差数の最小(ring_crossing_asc)" ],
    [ :max_ring_crossing_count, :integer, "円環交差数の最大(ring_crossing_desc)" ]
  ].freeze

  # 並び替え用の代表読み。prefix インデックスは ORDER BY に使えないため、
  # 全長インデックスを張れる 255 字(utf8mb4 で 1020 バイト)に収める。
  # 照合順序は word_senses.reading と揃える(清濁を区別する as_ci)。
  READING_KEY_COLUMNS = [
    [ :min_reading, "五十音順の代表読み(kana_asc)。word_senses.reading の最小を255字まで" ],
    [ :max_reading, "五十音順の代表読み(kana_desc)。word_senses.reading の最大を255字まで" ],
    [ :min_reversed_reading, "逆引き順の代表読み(reverse_kana)。読みを反転した最小を255字まで" ]
  ].freeze

  # ORDER BY と1対1に対応する索引。[WordSort のキー, カラム列, 並び]
  SORT_INDEXES = [
    [ "kana_asc", [ :min_reading, :id ], {} ],
    [ "kana_desc", [ :max_reading, :id ], { max_reading: :desc } ],
    [ "length_asc", [ :min_reading_length, :id ], {} ],
    [ "reverse_kana", [ :min_reversed_reading, :id ], {} ],
    [ "length_desc", [ :max_reading_length, :id ], { max_reading_length: :desc } ],
    [ "mora_desc", [ :max_mora_count, :id ], { max_mora_count: :desc } ],
    [ "surface_length_desc", [ :surface_length, :id ], { surface_length: :desc } ],
    [ "reading_density_desc", [ :reading_density, :id ], { reading_density: :desc } ],
    [ "small_kana_desc", [ :max_small_kana_count, :id ], { max_small_kana_count: :desc } ],
    [ "chouon_desc", [ :max_chouon_count, :id ], { max_chouon_count: :desc } ],
    [ "dakuten_desc", [ :max_dakuten_count, :id ], { max_dakuten_count: :desc } ],
    [ "ring_crossing_desc", [ :max_ring_crossing_count, :id ], { max_ring_crossing_count: :desc } ],
    # 少ない順は同値のとき読みが長い語を上位にするため、3カラムの複合にする。
    [ "ring_crossing_asc", [ :min_ring_crossing_count, :max_reading_length, :id ],
      { max_reading_length: :desc } ],
    [ "sense_count_desc", [ :sense_count, :id ], { sense_count: :desc } ],
    [ "variant_count_desc", [ :variant_count, :id ], { variant_count: :desc } ],
    [ "feature_count_desc", [ :feature_count, :id ], { feature_count: :desc } ]
  ].freeze

  def up
    COUNT_COLUMNS.each do |name, comment|
      add_column :words, name, :integer, null: false, default: 0, comment: comment
    end
    METRIC_COLUMNS.each do |name, type, comment|
      add_column :words, name, type, null: true, comment: comment
    end
    READING_KEY_COLUMNS.each do |name, comment|
      add_column :words, name, :string, limit: WordSenseMetrics::READING_KEY_LIMIT,
                        collation: "utf8mb4_0900_as_ci", comment: comment
    end

    # 表層形から一意に決まる値は STORED 生成カラムにする(Ruby 側で持たなくてよい)。
    # 生成式にマルチバイト文字を含めると schema.rb のダンプが壊れる既知の制限があるため、
    # 式は ASCII だけで書ける2つに限る(CLAUDE.md「生成カラム」参照)。
    add_column :words, :surface_length, :virtual, type: :integer, stored: true,
                       as: "CHAR_LENGTH(surface)",
                       comment: "表層形の文字数(surface_length_desc)"
    add_column :words, :reading_density, :virtual, type: :decimal, precision: 10, scale: 4, stored: true,
                       as: "max_reading_length / NULLIF(CHAR_LENGTH(surface), 0)",
                       comment: "1字あたりの読みの長さ(reading_density_desc)"

    SORT_INDEXES.each do |key, columns, order|
      add_index :words, columns, order: order, name: "idx_words_sort_#{key}"
    end

    # 既存行を埋める(1文の UPDATE)。
    WordSenseMetrics.refresh!
  end

  def down
    SORT_INDEXES.each { |key, _, _| remove_index :words, name: "idx_words_sort_#{key}" }
    remove_column :words, :reading_density
    remove_column :words, :surface_length
    READING_KEY_COLUMNS.each { |name, _| remove_column :words, name }
    METRIC_COLUMNS.each { |name, _, _| remove_column :words, name }
    COUNT_COLUMNS.each { |name, _| remove_column :words, name }
  end
end
