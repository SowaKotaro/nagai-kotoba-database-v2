class CreateWordSenses < ActiveRecord::Migration[8.1]
  def change
    # 語義。word に対し 1:多(同音異義語対応)。genre_id は末端(小分類)を指す。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :word_senses, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :word_id, null: false
      t.bigint :genre_id, null: true, comment: "小分類(末端)を指す"
      t.bigint :entity_type_id, null: true
      t.bigint :part_of_speech_id, null: true
      t.string :reading, null: false, limit: 768, comment: "読み"
      t.string :rhythm_pattern, null: true, limit: 2048, comment: "韻パターン(読みのローマ字表記)"
      t.text :meaning, null: true, comment: "意味"

      # reading からの派生値(STORED 生成カラム)。CHAR_LENGTH なので「きゃ」は 2 文字として数える。
      # rhythm_pattern(ローマ字)は SQL で生成できないため Ruby 側(RhythmPattern)で設定する。
      t.virtual :reading_length, type: :integer, as: "CHAR_LENGTH(reading)", stored: true, comment: "読みの文字数"
      t.virtual :first_char, type: :string, limit: 8, as: "LEFT(reading, 1)", stored: true, comment: "先頭文字"
      t.virtual :last_char, type: :string, limit: 8, as: "RIGHT(reading, 1)", stored: true, comment: "末尾文字"

      t.timestamps

      t.index :word_id, name: "idx_word_senses_word"
      t.index :genre_id, name: "idx_word_senses_genre"
      t.index :entity_type_id, name: "idx_word_senses_entity_type"
      t.index :part_of_speech_id, name: "idx_word_senses_part_of_speech"
      # utf8mb4 のインデックスキー長制限対策で reading は先頭191文字を対象にする。
      t.index :reading, length: 191, name: "idx_word_senses_reading"
      t.index :reading_length, name: "idx_word_senses_reading_length"
      t.index :first_char, name: "idx_word_senses_first_char"
      t.index :last_char, name: "idx_word_senses_last_char"
    end

    add_foreign_key :word_senses, :words, column: :word_id, name: "fk_word_senses_word"
    add_foreign_key :word_senses, :genres, column: :genre_id, name: "fk_word_senses_genre"
    add_foreign_key :word_senses, :entity_types, column: :entity_type_id, name: "fk_word_senses_entity_type"
    add_foreign_key :word_senses, :parts_of_speech, column: :part_of_speech_id, name: "fk_word_senses_part_of_speech"
  end
end
