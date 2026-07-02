class CreatePartsOfSpeech < ActiveRecord::Migration[8.1]
  def change
    # 品詞の単純マスタ。テーブル名は parts_of_speech(不規則複数形。inflections.rb 参照)。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :parts_of_speech, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, null: false

      t.timestamps

      t.index :name, unique: true, name: "uq_parts_of_speech_name"
    end
  end
end
