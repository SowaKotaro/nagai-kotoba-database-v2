class CreateGenres < ActiveRecord::Migration[8.1]
  def change
    # ジャンルは隣接リスト(parent_id)で 大(level1)→中(level2)→小(level3) の3階層を表現する。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :genres, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      # 親ジャンル(自己参照)。level1(大分類)は親を持たないため NULL 許容。
      t.references :parent, null: true, foreign_key: { to_table: :genres }
      t.integer :level, null: false, limit: 1, comment: "1=大分類, 2=中分類, 3=小分類"
      t.string :name, null: false

      t.timestamps

      # 同じ親の下で同名を許さない。
      # ただし MySQL は NULL を区別するため、level1(parent_id=NULL)の同名重複は
      # DB では防げない。level1 の一意性はモデルの uniqueness で担保する。
      t.index [ :parent_id, :name ], unique: true, name: "uq_genres_parent_name"
      t.index :level, name: "idx_genres_level"
    end
  end
end
