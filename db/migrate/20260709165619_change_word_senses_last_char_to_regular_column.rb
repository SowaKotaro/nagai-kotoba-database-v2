class ChangeWordSensesLastCharToRegularColumn < ActiveRecord::Migration[8.1]
  # last_char(末尾文字)を SQL の STORED 生成カラムから通常カラムへ変更する。
  #
  # 背景: 末尾が長音符「ー」の場合に単純な RIGHT(reading, 1) だと「ー」自体が
  # 末尾文字になってしまう問題を直すには、生成式に「ー」(マルチバイト文字)を
  # 含める必要がある。しかし ActiveRecord の SchemaDumper(MySQL2 アダプタ)が
  # information_schema 経由で生成式を取得する際に文字化けし、schema.rb が壊れる
  # 既知の制限があるため、last_char だけは Ruby 側(WordSense#assign_reading_derivations
  # / LastChar)で計算する通常カラムに切り替える。
  CHOUON = "ー"

  def up
    remove_column :word_senses, :last_char
    add_column :word_senses, :last_char, :string, limit: 8,
      comment: "末尾文字(末尾の長音「ー」は除く。reading から Ruby 側で計算)"
    add_index :word_senses, :last_char, name: "idx_word_senses_last_char"

    backfill_last_char
  end

  def down
    remove_column :word_senses, :last_char
    add_column :word_senses, :last_char, :virtual, type: :string, limit: 8,
      as: "right(`reading`, 1)", stored: true, comment: "末尾文字"
    add_index :word_senses, :last_char, name: "idx_word_senses_last_char"
  end

  private

  def backfill_last_char
    select_all("SELECT id, reading FROM word_senses").each do |row|
      text = row["reading"].to_s.sub(/#{CHOUON}+\z/, "")
      last_char = text.empty? ? nil : text[-1]
      execute("UPDATE word_senses SET last_char = #{quote(last_char)} WHERE id = #{row['id']}")
    end
  end
end
