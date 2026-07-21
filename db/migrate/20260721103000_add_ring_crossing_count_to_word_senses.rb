class AddRingCrossingCountToWordSenses < ActiveRecord::Migration[8.1]
  # 円環交差数(五十音円環に読みを結んだ折れ線どうしが交わる回数)を保存する。
  #
  # 交差判定は弦の総当たりで、SQL では書けないため mora_count と同様に Ruby 側
  # (KanaRing)で計算し、WordSense の before_validation で自動セットする。
  # ランキング(WordRanking)と単語一覧の並び替え(WordSort)から SQL で並べたいので、
  # 値をカラムに落としてインデックスを張る。
  def up
    add_column :word_senses, :ring_crossing_count, :integer, null: true,
                                                   comment: "円環交差数(五十音円環で読みを結んだ線の交差回数)"
    add_index :word_senses, :ring_crossing_count, name: "idx_word_senses_ring_crossing_count"

    backfill_ring_crossing_count
  end

  def down
    remove_column :word_senses, :ring_crossing_count
  end

  private

  # 既存の語義を埋める。計算式は KanaRing だけが持つ規則(濁音の畳み方・長音符の除外)に
  # 依存するため、last_char のときのように SQL へ書き下さず値オブジェクトを直接使う。
  def backfill_ring_crossing_count
    select_all("SELECT id, reading FROM word_senses").each do |row|
      count = KanaRing.crossing_count(row["reading"])
      execute("UPDATE word_senses SET ring_crossing_count = #{quote(count)} WHERE id = #{row['id']}")
    end
  end
end
