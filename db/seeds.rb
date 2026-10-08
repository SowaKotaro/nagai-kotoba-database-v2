# デプロイのたびに deploy:migrate の直後で流れる(config/deploy.rb の deploy:seed)。
# 何度流しても同じ結果になるように書く。

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
  # ログイン ID は出さない(出力はデプロイのログに残り、リポジトリが公開なので誰でも読める)。
  puts "管理者を作成/更新しました。"
else
  puts "管理者の認証情報が未設定のためスキップしました。" \
       "ADMIN_USERNAME / ADMIN_PASSWORD か credentials の admin: を設定してください。"
end

# マスタ(ジャンル・語種・品詞・言語学的特徴)を投入する。
# 名前リストとリネーム追従マップは app/models/seed_catalog.rb が単一の正
# (管理画面のタグ統括管理と共有。運用ルールも同ファイルのコメント参照)。
SeedCatalog.seed_all!

# 開発環境のみ: 統計ページ等を本番相当のボリュームで確認するためのダミーデータ。
# 本番・テストには投入しない(deploy:seed でも走らない)。
load Rails.root.join("db/seeds/development.rb") if Rails.env.development?
