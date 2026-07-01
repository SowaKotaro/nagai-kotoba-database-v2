class UnifyCollationToUtf8mb40900AiCi < ActiveRecord::Migration[8.1]
  # 日本語検索方針に合わせ、既存テーブルの照合順序を utf8mb4_0900_ai_ci に統一する。
  # admins / sessions は少数レコードのため変換の影響は軽微。
  TABLES = %w[admins sessions].freeze

  def up
    TABLES.each do |table|
      execute "ALTER TABLE #{table} CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"
    end
  end

  def down
    TABLES.each do |table|
      execute "ALTER TABLE #{table} CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"
    end
  end
end
