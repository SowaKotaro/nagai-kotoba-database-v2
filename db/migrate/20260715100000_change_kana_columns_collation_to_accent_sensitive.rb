class ChangeKanaColumnsCollationToAccentSensitive < ActiveRecord::Migration[8.1]
  # 検索で清音・濁音・半濁音を区別する。
  #
  # 背景: これまでの utf8mb4_0900_ai_ci はアクセント(濁点・半濁点)非区別のため、
  # MySQL 上で「ハ = バ = パ」「ウ = ヴ」が同一視され、先頭文字・末尾文字の絞り込み、
  # 50音索引(GROUP BY first_char)の集計、キーワード検索がすべて清音に畳まれていた。
  # 読み・表層形まわりのカラムだけを utf8mb4_0900_as_ci(アクセント区別・大文字小文字
  # 非区別)へ変更する。ひらがな⇔カタカナ、A⇔a の同一視(緩いキーワード検索)は保つ。
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
    # first_char は reading から作る STORED 生成カラム。基底カラムの変更が制限される
    # 場合があるため、いったん外してから reading を変更し、作り直す。生成カラムの
    # 照合順序は表の既定(ai_ci)に従ってしまうため、明示的に指定する。
    remove_column :word_senses, :first_char
    change_column :word_senses, :reading, :string, limit: 768, null: false,
      collation: collation, comment: "読み"
    add_column :word_senses, :first_char, :virtual, type: :string, limit: 8,
      as: "LEFT(reading, 1)", stored: true, collation: collation, comment: "先頭文字"
    add_index :word_senses, :first_char, name: "idx_word_senses_first_char"

    change_column :word_senses, :last_char, :string, limit: 8,
      collation: collation, comment: "末尾文字(末尾の長音「ー」は除く。reading から Ruby 側で計算)"
    change_column :words, :surface, :string, limit: 768, null: false,
      collation: collation, comment: "表層形 例: ABC殺人事件"
  end
end
