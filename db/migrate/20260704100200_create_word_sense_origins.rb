class CreateWordSenseOrigins < ActiveRecord::Migration[8.1]
  def change
    # 語義 × 語種 の多対多を表す中間テーブル。
    # 混種語(例: 歯ブラシ = 和語 + 英語)を表現できるよう 1 語義に複数の語種を付与できる。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :word_sense_origins, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :word_sense_id, null: false
      t.bigint :word_origin_id, null: false

      t.timestamps

      # 同じ語義に同じ語種を二重登録させない。
      # (word_sense_id を先頭に含むため word_sense_id 単独の索引も兼ねる)
      t.index [ :word_sense_id, :word_origin_id ], unique: true, name: "uq_wso_sense_origin"
      t.index :word_origin_id, name: "idx_wso_origin"
    end

    add_foreign_key :word_sense_origins, :word_senses, column: :word_sense_id, name: "fk_wso_word_sense"
    add_foreign_key :word_sense_origins, :word_origins, column: :word_origin_id, name: "fk_wso_word_origin"
  end
end
