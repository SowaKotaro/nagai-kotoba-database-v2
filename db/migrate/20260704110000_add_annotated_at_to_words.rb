class AddAnnotatedAtToWords < ActiveRecord::Migration[8.1]
  def change
    # アノテーション・コンソールの「未注釈キュー」を駆動するための時刻。
    # 保存時に現在時刻をセットし、NULL の語を未注釈として順に流す。
    add_column :words, :annotated_at, :datetime, null: true, comment: "アノテーション完了時刻(未注釈は NULL)"
    add_index :words, :annotated_at, name: "idx_words_annotated_at"
  end
end
