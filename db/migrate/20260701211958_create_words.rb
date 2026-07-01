class CreateWords < ActiveRecord::Migration[8.1]
  def change
    # 単語の表層形(surface)を保持する。char_type_pattern は surface から Ruby 側で生成する。
    create_table :words, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :surface, null: false, limit: 768, comment: "表層形 例: ABC殺人事件"
      t.string :char_type_pattern, null: false, limit: 768, comment: "文字タイプ列 例: AAA漢漢漢漢"

      t.timestamps

      # utf8mb4 のインデックスキー長制限(3072byte)対策で先頭191文字を対象にする。
      t.index :surface, unique: true, length: 191, name: "uq_words_surface"
      t.index :char_type_pattern, length: 191, name: "idx_words_char_type_pattern"
    end
  end
end
