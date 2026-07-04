# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# 管理者（オーナー）を1名作成する。
# 認証情報は credentials（config/credentials.yml.enc の admin: username / password）か、
# 環境変数 ADMIN_USERNAME / ADMIN_PASSWORD から読み込む。コードには直書きしない。
admin_credentials = Rails.application.credentials.admin || {}
admin_username = ENV["ADMIN_USERNAME"] || admin_credentials[:username]
admin_password = ENV["ADMIN_PASSWORD"] || admin_credentials[:password]

if admin_username.present? && admin_password.present?
  admin = Admin.find_or_initialize_by(username: admin_username)
  admin.password = admin_password
  admin.save!
  puts "管理者を作成/更新しました: #{admin.username}"
else
  puts "管理者の認証情報が未設定のためスキップしました。" \
       "ADMIN_USERNAME / ADMIN_PASSWORD か credentials の admin: を設定してください。"
end

# ジャンル(大分類・中分類)のマスタを投入する。
load Rails.root.join("db/seeds/genres.rb")

# 語種(和語・漢語・各言語)のマスタを投入する。
load Rails.root.join("db/seeds/word_origins.rb")

# 品詞のマスタを投入する。
load Rails.root.join("db/seeds/parts_of_speech.rb")

# 言語学的特徴のマスタを投入する。
load Rails.root.join("db/seeds/linguistic_features.rb")

# 初期の単語コーパス(表層形・読み)は開発/テストでの操作確認用のサンプルデータ。
# 本番では自動投入しない(自動デプロイの deploy:seed に載せない)。
# 本番の単語は管理者が実際に登録したものだけにして、ID/created_at をクリーンに保つ。
load Rails.root.join("db/seeds/words.rb") unless Rails.env.production?
