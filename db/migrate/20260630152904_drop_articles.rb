class DropArticles < ActiveRecord::Migration[8.1]
  def change
    drop_table :articles do |t|
      t.string :title
      t.text :body

      t.timestamps
    end
  end
end
