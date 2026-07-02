class CreateWordSenseFeatures < ActiveRecord::Migration[8.1]
  def change
    # 語義 × 言語学的特徴の多対多を表す中間テーブル。
    # 特徴は単語の「該当部分」ごとに付与する(例:「硫黄島からの手紙」に 連濁:硫黄島 と 連濁:手紙)。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :word_sense_features, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :word_sense_id, null: false
      t.bigint :linguistic_feature_id, null: false
      t.string :target, null: false, limit: 768, comment: "該当部分(表層形の一部) 例: 硫黄島"
      t.string :target_reading, null: false, limit: 768, comment: "該当部分の読み 例: イオウジマ"

      t.timestamps

      # 同じ語義×特徴でも該当部分が異なれば複数登録できる。三つ組の重複だけを禁止する。
      # utf8mb4 のインデックスキー長制限対策で target は先頭191文字を対象にする。
      # (word_sense_id を先頭に含むため word_sense_id 単独の索引も兼ねる)
      t.index [ :word_sense_id, :linguistic_feature_id, :target ],
              unique: true, length: { target: 191 }, name: "uq_wsf_sense_feature_target"
      t.index :linguistic_feature_id, name: "idx_wsf_feature"
    end

    add_foreign_key :word_sense_features, :word_senses, column: :word_sense_id, name: "fk_wsf_word_sense"
    add_foreign_key :word_sense_features, :linguistic_features, column: :linguistic_feature_id, name: "fk_wsf_linguistic_feature"
  end
end
