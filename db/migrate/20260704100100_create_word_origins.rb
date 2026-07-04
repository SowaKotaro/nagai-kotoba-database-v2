class CreateWordOrigins < ActiveRecord::Migration[8.1]
  def change
    # 語種の単純マスタ(和語 / 漢語 / 英語 / フランス語 …)。
    # 「外来語」で束ねず言語ごとに切り分けるため、値が増える開いた集合としてマスタで持つ。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :word_origins, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, null: false

      t.timestamps

      t.index :name, unique: true, name: "uq_word_origins_name"
    end
  end
end
