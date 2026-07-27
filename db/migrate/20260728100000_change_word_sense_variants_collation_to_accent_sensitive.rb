class ChangeWordSenseVariantsCollationToAccentSensitive < ActiveRecord::Migration[8.1]
  # 別表記(表層形・読み)を検索の対象にする(Issue 72)にあたり、照合順序を
  # 本体の表層形・読み(words.surface / word_senses.reading)と揃える。
  #
  # 既定の utf8mb4_0900_ai_ci は濁点・半濁点を非区別(ハ = バ = パ)にするため、
  # 別表記だけ清濁が畳まれて一致してしまう。utf8mb4_0900_as_ci なら清濁を区別しつつ、
  # ひらがな⇔カタカナ・A⇔a の同一視(緩いキーワード検索)は保てる。
  #
  # UNIQUE KEY uq_wsv_sense_surface は as_ci の方が値を区別する向きなので、
  # 既存行が衝突することはない(索引が張り直されるだけ)。
  OLD_COLLATION = "utf8mb4_0900_ai_ci"
  NEW_COLLATION = "utf8mb4_0900_as_ci"

  def up
    change_collations(NEW_COLLATION)
  end

  def down
    change_collations(OLD_COLLATION)
  end

  private

  def change_collations(collation)
    change_column :word_sense_variants, :surface, :string, limit: 768, null: false,
      collation: collation, comment: "別表記の表層形 例: バタフライ効果"
    change_column :word_sense_variants, :reading, :string, limit: 768,
      collation: collation, comment: "別表記の読み(変わる場合) 例: バタフライこうか"
  end
end
