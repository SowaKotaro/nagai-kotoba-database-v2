# アノテーション状態(未対応/保留/完了)を words に持たせる。
# 従来は annotated_at の有無だけで「未注釈 / 注釈済み」の2値だったが、
# 「一度保留してキューから外したい」語を表せるよう保留(on_hold)を足して3値にする。
# 完了(2)は annotated_at ありと一致させる(公開条件は従来どおり annotated_at で判定)。
class AddAnnotationStatusToWords < ActiveRecord::Migration[8.1]
  def up
    add_column :words, :annotation_status, :integer, null: false, default: 0,
               comment: "アノテーション状態(0:未対応/1:保留/2:完了)"
    add_index :words, :annotation_status, name: "idx_words_annotation_status"

    # 既存データの移行: annotated_at ありは完了(2)へ。未対応/保留は既定の 0 のまま。
    execute "UPDATE words SET annotation_status = 2 WHERE annotated_at IS NOT NULL"
  end

  def down
    remove_index :words, name: "idx_words_annotation_status"
    remove_column :words, :annotation_status
  end
end
