class CreateEntityTypes < ActiveRecord::Migration[8.1]
  def change
    # エンティティタイプの単純マスタ(人名 / 書籍名 など)。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :entity_types, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, null: false

      t.timestamps

      t.index :name, unique: true, name: "uq_entity_types_name"
    end
  end
end
