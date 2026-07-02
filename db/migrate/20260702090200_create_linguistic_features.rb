class CreateLinguisticFeatures < ActiveRecord::Migration[8.1]
  def change
    # 言語学的特徴の単純マスタ(連濁 / 重箱読み / 湯桶読み など)。※語義とは多対多(Issue 6)。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :linguistic_features, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, null: false

      t.timestamps

      t.index :name, unique: true, name: "uq_linguistic_features_name"
    end
  end
end
